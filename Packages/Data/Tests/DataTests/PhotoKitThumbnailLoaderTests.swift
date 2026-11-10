import CoreGraphics
import DataLayer
import Foundation
import Photos
import Testing

/// Records cache calls of `PhotoKitThumbnailLoader`.
private final class FakeThumbnailCache: ThumbnailCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var startedIDs: [[String]] = []
    private var stoppedIDs: [[String]] = []
    private var stopAllCount = 0

    var started: [[String]] { locked { startedIDs } }
    var stopped: [[String]] { locked { stoppedIDs } }
    var stopAllCalls: Int { locked { stopAllCount } }

    /// Records the IDs.
    func startCaching(assetIDs: [String], targetSize: CGSize) {
        locked { startedIDs.append(assetIDs) }
    }

    /// Records the IDs.
    func stopCaching(assetIDs: [String], targetSize: CGSize) {
        locked { stoppedIDs.append(assetIDs) }
    }

    /// Counts the call.
    func stopCachingAll() {
        locked { stopAllCount += 1 }
    }

    /// Runs `body` while holding the lock.
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Streams, cancellation and the bounded prefetch window of `PhotoKitThumbnailLoader`.
struct PhotoKitThumbnailLoaderTests {
    private let size = CGSize(width: 264, height: 264)

    /// A first `.opportunistic` callback: a small image marked degraded.
    private func degraded() throws -> ImageRequestResult {
        var result = try ImageTestSupport.success()
        result.isDegraded = true
        return result
    }

    // MARK: - Options

    @Test func thumbnailRequestsAreOpportunisticLocalOnlyAndFast() {
        let options = PhotoKitThumbnailRequester.makeOptions()
        #expect(options.isNetworkAccessAllowed == false)
        #expect(options.deliveryMode == .opportunistic)
        #expect(options.resizeMode == .fast)
        #expect(options.version == .current)
        #expect(options.isSynchronous == false)
        #expect(PhotoKitThumbnailRequester.contentMode == .aspectFill)
    }

    // MARK: - Streams

    @Test func yieldsTheDegradedThenTheFinalImageAndFinishes() async throws {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitThumbnailLoader(requester: requester, cache: FakeThumbnailCache())
        var iterator = loader.thumbnail(for: "a", size: size).makeAsyncIterator()
        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 1 })

        requester.answerFirstHeld(with: try degraded())
        let degradedImage = await iterator.next()
        #expect(degradedImage != nil, "The degraded image is shown first")
        requester.releaseFirstHeld(with: try ImageTestSupport.success(orientation: .right))
        let finalImage = await iterator.next()
        #expect(finalImage?.orientation == .right)
        let end = await iterator.next()
        #expect(end == nil, "The final image ends the stream")
        #expect(requester.requestedSizes == [size])
        #expect(requester.cancelledRequestIDs.isEmpty)
    }

    @Test func aMissingPhotoFinishesWithoutAnImage() async {
        let loader = PhotoKitThumbnailLoader(
            requester: MockImageRequester(defaultBehavior: .missing),
            cache: FakeThumbnailCache()
        )
        var count = 0
        for await _ in loader.thumbnail(for: "gone", size: size) {
            count += 1
        }
        #expect(count == 0)
    }

    @Test func aCloudOnlyPhotoKeepsItsDegradedImageAndFinishes() async throws {
        let cloud = ImageRequestResult(isInCloud: true)
        let requester = MockImageRequester(defaultBehavior: .respond([try degraded(), cloud]))
        let loader = PhotoKitThumbnailLoader(requester: requester, cache: FakeThumbnailCache())
        var images = 0
        for await _ in loader.thumbnail(for: "cloud", size: size) {
            images += 1
        }
        #expect(images == 1)
    }

    @Test func endingTheStreamCancelsTheRequestInFlight() async {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let loader = PhotoKitThumbnailLoader(requester: requester, cache: FakeThumbnailCache())
        let stream = loader.thumbnail(for: "a", size: size)
        let consumer = Task {
            for await _ in stream {}
        }
        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 1 })
        consumer.cancel()
        await consumer.value
        #expect(await ImageTestSupport.waitUntil { requester.allHeldRequestsCancelled })
    }

    // MARK: - Prefetch window

    @Test func prefetchIsBoundedAndReleasesTheOldestFirst() async {
        let cache = FakeThumbnailCache()
        let loader = PhotoKitThumbnailLoader(
            requester: MockImageRequester(defaultBehavior: .missing),
            cache: cache,
            maxCachedAssets: 3
        )
        await loader.prefetch(["a", "b"], size: size)
        await loader.prefetch(["b", "c", "d", "e"], size: size)
        #expect(cache.started == [["a", "b"], ["c", "d", "e"]], "Photos already cached are not started again")
        #expect(cache.stopped == [["a", "b"]])
        #expect(await loader.cachedAssetIDs(size: size) == ["c", "d", "e"])
    }

    @Test func stopPrefetchingReleasesOnlyCachedPhotos() async {
        let cache = FakeThumbnailCache()
        let loader = PhotoKitThumbnailLoader(requester: MockImageRequester(defaultBehavior: .missing), cache: cache)
        await loader.prefetch(["a", "b"], size: size)
        await loader.stopPrefetching(["b", "x"], size: size)
        #expect(cache.stopped == [["b"]])
        #expect(await loader.cachedAssetIDs(size: size) == ["a"])

        await loader.stopAllPrefetching()
        #expect(cache.stopAllCalls == 1)
        #expect(await loader.cachedAssetIDs(size: size).isEmpty)
    }
}
