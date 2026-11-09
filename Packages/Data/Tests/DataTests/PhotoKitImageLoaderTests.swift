import CoreGraphics
import DataLayer
import Domain
import Foundation
import Photos
import Testing

struct PhotoKitImageLoaderTests {
    private let size = ImageLoadingDefaults.targetSize

    private static func ids(_ count: Int) -> [String] {
        (0..<count).map { "asset-\($0)" }
    }

    /// Runs `loadImage` and returns the error it threw, or `nil` if it succeeded.
    private func loadError(_ loader: PhotoKitImageLoader, assetID: String = "a") async -> ImageLoadError? {
        do {
            _ = try await loader.loadImage(assetID: assetID, targetSize: size)
            return nil
        } catch {
            return error as? ImageLoadError
        }
    }

    // MARK: - Request options

    @Test func analysisRequestsAreLocalOnlyHighQualityAndFast() {
        let options = PhotoKitImageRequester.makeOptions()
        #expect(options.isNetworkAccessAllowed == false)
        #expect(options.deliveryMode == .highQualityFormat)
        #expect(options.resizeMode == .fast)
        #expect(options.version == .current)
        #expect(options.isSynchronous == false)
        #expect(PhotoKitImageRequester.contentMode == .aspectFit)
    }

    @Test func defaultsAre512PixelsAndAtMostFourRequests() {
        #expect(ImageLoadingDefaults.targetSize == CGSize(width: 512, height: 512))
        let expected = min(4, ProcessInfo.processInfo.activeProcessorCount)
        #expect(ImageLoadingDefaults.maxConcurrent == expected)
    }

    // MARK: - Single image

    @Test func returnsTheImageWithItsOrientation() async throws {
        let callback = try ImageTestSupport.success(orientation: .right)
        let loader = PhotoKitImageLoader(requester: MockImageRequester(defaultBehavior: .respond([callback])))
        let image = try await loader.loadImage(assetID: "a", targetSize: size)
        #expect(image.orientation == .right)
        #expect(image.cgImage.width == 4)
    }

    @Test func missingAssetIsNotFound() async {
        let loader = PhotoKitImageLoader(requester: MockImageRequester(defaultBehavior: .missing))
        #expect(await loadError(loader) == .notFound)
    }

    @Test(arguments: [
        (ImageRequestResult(isInCloud: true), ImageLoadError.iCloudOnly),
        (ImageRequestResult(), .decodeFailed),
        (ImageRequestResult(hasError: true), .decodeFailed),
        (ImageRequestResult(isCancelled: true), .cancelled)
    ])
    func failedCallbacksMapToSkipReasons(callback: ImageRequestResult, expected: ImageLoadError) async {
        let loader = PhotoKitImageLoader(requester: MockImageRequester(defaultBehavior: .respond([callback])))
        #expect(await loadError(loader) == expected)
    }

    @Test func aDegradedStandInForAnICloudOriginalIsSkippedNotAwaited() async throws {
        var degraded = try ImageTestSupport.success()
        degraded.isDegraded = true
        degraded.isInCloud = true
        let loader = PhotoKitImageLoader(requester: MockImageRequester(defaultBehavior: .respond([degraded])))
        #expect(await loadError(loader) == .iCloudOnly)
    }

    @Test func aSecondCallbackIsIgnored() async throws {
        let first = try ImageTestSupport.success(orientation: .left)
        let second = try ImageTestSupport.success(orientation: .down)
        let callbacks = [first, second, ImageRequestResult(isCancelled: true)]
        let loader = PhotoKitImageLoader(requester: MockImageRequester(defaultBehavior: .respond(callbacks)))
        let image = try await loader.loadImage(assetID: "a", targetSize: size)
        #expect(image.orientation == .left)
    }

    @Test func cancellingTheTaskCancelsTheRequestAndALateCallbackIsIgnored() async throws {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitImageLoader(requester: requester)
        let task = Task { try await loader.loadImage(assetID: "a", targetSize: ImageLoadingDefaults.targetSize) }
        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 1 })

        task.cancel()
        await #expect(throws: ImageLoadError.cancelled) { try await task.value }
        #expect(requester.cancelledRequestIDs.count == 1)

        requester.releaseAllHeld(with: try ImageTestSupport.success())
    }

    @Test func skipReasonsForTheScanSummary() {
        #expect(ImageLoadError.iCloudOnly.skipReason == .iCloudOnly)
        #expect(ImageLoadError.decodeFailed.skipReason == .decodeFailed)
        #expect(ImageLoadError.notFound.skipReason == .notFound)
        #expect(ImageLoadError.cancelled.skipReason == nil)
    }

    // MARK: - Batches

    @Test func batchDeliversEveryPhotoOnceAndContinuesPastFailures() async throws {
        let requester = MockImageRequester(
            defaultBehavior: .respond([try ImageTestSupport.success()]),
            behaviors: [
                "asset-1": .respond([ImageRequestResult(isInCloud: true)]),
                "asset-3": .respond([ImageRequestResult()]),
                "asset-4": .missing
            ]
        )
        let loader = PhotoKitImageLoader(requester: requester)
        var results: [String: Result<LoadedImage, ImageLoadError>] = [:]
        for await outcome in loader.loadBatch(Self.ids(6), targetSize: size, maxConcurrent: 2) {
            #expect(results[outcome.assetID] == nil)
            results[outcome.assetID] = outcome.result
        }

        #expect(Set(results.keys) == Set(Self.ids(6)))
        let skips = results.compactMapValues { result -> SkipReason? in
            if case .failure(let error) = result { return error.skipReason }
            return nil
        }
        #expect(skips == ["asset-1": .iCloudOnly, "asset-3": .decodeFailed, "asset-4": .notFound])
    }

    @Test func batchNeverHasMoreThanMaxConcurrentRequestsInFlight() async throws {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitImageLoader(requester: requester)
        let stream = loader.loadBatch(Self.ids(10), targetSize: size, maxConcurrent: 3)
        let consumer = Task {
            var delivered: [String] = []
            for await outcome in stream {
                delivered.append(outcome.assetID)
            }
            return delivered
        }

        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 3 })
        let success = try ImageTestSupport.success()
        for _ in 0..<10 {
            #expect(await ImageTestSupport.waitUntil { requester.heldCount > 0 })
            requester.releaseFirstHeld(with: success)
        }
        let delivered = await consumer.value

        #expect(delivered.count == 10)
        #expect(Set(delivered) == Set(Self.ids(10)))
        #expect(requester.maxHeldAtOnce == 3)
    }

    @Test func batchDoesNotLoadAheadOfItsConsumer() async throws {
        let requester = MockImageRequester(defaultBehavior: .respond([try ImageTestSupport.success()]))
        let loader = PhotoKitImageLoader(requester: requester)
        let stream = loader.loadBatch(Self.ids(20), targetSize: size, maxConcurrent: 2)
        try await Task.sleep(for: .milliseconds(50))
        #expect(requester.requestedAssetIDs.isEmpty)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
        try await Task.sleep(for: .milliseconds(100))
        // One outcome taken, at most two more loaded and waiting: the window never runs further ahead.
        #expect(requester.requestedAssetIDs.count == 3)
    }

    @Test func cancellingTheConsumerCancelsPendingRequestsWithin200Milliseconds() async throws {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitImageLoader(requester: requester)
        let stream = loader.loadBatch(Self.ids(10), targetSize: size, maxConcurrent: 4)
        let consumer = Task {
            for await _ in stream {}
        }
        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 4 })

        let start = ContinuousClock.now
        consumer.cancel()
        let allCancelled = await ImageTestSupport.waitUntil(timeout: .seconds(1)) {
            requester.cancelledRequestIDs.count == 4
        }
        let elapsed = ContinuousClock.now - start

        #expect(allCancelled)
        #expect(elapsed < .milliseconds(200))
        await consumer.value
        #expect(requester.requestedAssetIDs.count == 4)
        requester.releaseAllHeld(with: try ImageTestSupport.success())
    }
}

#if canImport(UIKit)
import UIKit

struct PhotoKitImageOrientationTests {
    @Test(arguments: [
        (UIImage.Orientation.up, CGImagePropertyOrientation.up),
        (.upMirrored, .upMirrored),
        (.down, .down),
        (.downMirrored, .downMirrored),
        (.left, .left),
        (.leftMirrored, .leftMirrored),
        (.right, .right),
        (.rightMirrored, .rightMirrored)
    ])
    func mapsEveryUIImageOrientation(orientation: UIImage.Orientation, expected: CGImagePropertyOrientation) {
        #expect(PhotoKitImageRequester.orientation(of: orientation) == expected)
    }
}
#endif
