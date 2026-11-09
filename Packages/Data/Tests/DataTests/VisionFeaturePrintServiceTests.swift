import CoreGraphics
import DataLayer
import Domain
import Foundation
import Testing

struct VisionFeaturePrintServiceTests {
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// A photo whose creation and modification dates are `modificationDate`.
    private func asset(_ id: String) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: modificationDate,
            modificationDate: modificationDate,
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A service over a real `PhotoKitImageLoader` backed by `requester`.
    private func makeService(
        requester: MockImageRequester,
        extractor: MockFeaturePrintExtractor,
        maxConcurrentRequests: Int = VisionFeaturePrintService.defaultMaxConcurrentRequests
    ) -> VisionFeaturePrintService {
        VisionFeaturePrintService(
            images: PhotoKitImageLoader(requester: requester),
            extractor: extractor,
            maxConcurrentRequests: maxConcurrentRequests
        )
    }

    /// A requester that answers every request at once with a small image.
    private func respondingRequester() throws -> MockImageRequester {
        MockImageRequester(defaultBehavior: .respond([try ImageTestSupport.success()]))
    }

    // MARK: - Results

    @Test func computesAPrintWithItsRevisionAndTheAssetsModificationDate() async throws {
        let requester = try respondingRequester()
        let extractor = MockFeaturePrintExtractor(revision: 2, vector: [0.5, 0.25])
        let service = makeService(requester: requester, extractor: extractor)

        let outcome = try await service.featurePrint(for: asset("a"))

        let expected = FeaturePrint(
            assetID: "a",
            revision: 2,
            vector: [0.5, 0.25],
            assetModificationDate: modificationDate
        )
        #expect(outcome == .computed(expected))
        #expect(service.revision == 2)
        #expect(requester.requestedSizes == [ImageLoadingDefaults.targetSize])
    }

    @Test func imagesThatCannotBeLoadedAreSkippedWithoutRunningVision() async throws {
        let cases: [(MockImageRequester.Behavior, SkipReason)] = [
            (.respond([ImageRequestResult(isInCloud: true)]), .iCloudOnly),
            (.respond([ImageRequestResult()]), .decodeFailed),
            (.missing, .notFound)
        ]
        for (behavior, reason) in cases {
            let extractor = MockFeaturePrintExtractor()
            let service = makeService(requester: MockImageRequester(defaultBehavior: behavior), extractor: extractor)
            #expect(try await service.featurePrint(for: asset("a")) == .skipped(reason))
            #expect(extractor.callCount == 0)
        }
    }

    @Test func aVisionErrorMarksThePhotoFailedAndTheNextPhotoIsStillAnalysed() async throws {
        let extractor = MockFeaturePrintExtractor(failingCalls: [1])
        let service = makeService(requester: try respondingRequester(), extractor: extractor)

        var outcomes: [FeaturePrintOutcome] = []
        for id in ["a", "b", "c"] {
            outcomes.append(try await service.featurePrint(for: asset(id)))
        }

        #expect(outcomes[0].featurePrint?.assetID == "a")
        #expect(outcomes[1] == .failed(.vision))
        #expect(outcomes[2].featurePrint?.assetID == "c")
    }

    // MARK: - Cancellation

    @Test func cancellingWhileTheImageLoadsThrowsCancellationAndSkipsVision() async throws {
        let requester = MockImageRequester(defaultBehavior: .hold)
        let extractor = MockFeaturePrintExtractor()
        let service = makeService(requester: requester, extractor: extractor)

        let task = Task { try await service.featurePrint(for: asset("a")) }
        #expect(await ImageTestSupport.waitUntil { requester.heldCount == 1 })
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(requester.allHeldRequestsCancelled)
        #expect(extractor.callCount == 0)
    }

    // MARK: - Threads and concurrency

    @Test func atMostTwoVisionRequestsRunAtOnceByDefault() async throws {
        #expect(VisionFeaturePrintService.defaultMaxConcurrentRequests == 2)
        let extractor = MockFeaturePrintExtractor(duration: 0.05)
        let service = makeService(requester: try respondingRequester(), extractor: extractor)

        try await analyse(count: 8, with: service)

        #expect(extractor.callCount == 8)
        #expect(extractor.maxCallsAtOnce == 2)
    }

    @Test(arguments: [1, 3])
    func theVisionLimitIsConfigurable(limit: Int) async throws {
        let extractor = MockFeaturePrintExtractor(duration: 0.05)
        let requester = try respondingRequester()
        let service = makeService(requester: requester, extractor: extractor, maxConcurrentRequests: limit)

        try await analyse(count: 8, with: service)

        #expect(extractor.maxCallsAtOnce == limit)
    }

    @MainActor
    @Test func visionNeverRunsOnTheMainThread() async throws {
        let extractor = MockFeaturePrintExtractor()
        let service = makeService(requester: try respondingRequester(), extractor: extractor)

        _ = try await service.featurePrint(for: asset("a"))

        #expect(extractor.callCount == 1)
        #expect(extractor.callsOnMainThread == 0)
    }

    /// Requests `count` prints at once, as the scan coordinator does with a task group.
    private func analyse(count: Int, with service: VisionFeaturePrintService) async throws {
        try await withThrowingTaskGroup(of: FeaturePrintOutcome.self) { group in
            for index in 0..<count {
                let photo = asset("asset-\(index)")
                group.addTask { try await service.featurePrint(for: photo) }
            }
            for try await outcome in group {
                #expect(outcome.featurePrint != nil)
            }
        }
    }
}
