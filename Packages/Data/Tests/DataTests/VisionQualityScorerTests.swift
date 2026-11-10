import CoreGraphics
@testable import DataLayer
import Domain
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct VisionQualityScorerTests {
    /// A photo with the given ID.
    private func asset(_ id: String) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A scorer over a real `PhotoKitImageLoader` backed by `requester`.
    private func makeScorer(
        requester: MockImageRequester,
        vision: MockQualityVisionExtractor = MockQualityVisionExtractor(),
        edits: MockAssetEditInspector = MockAssetEditInspector(),
        maxConcurrentRequests: Int = VisionQualityScorer.defaultMaxConcurrentRequests
    ) -> VisionQualityScorer {
        VisionQualityScorer(
            images: PhotoKitImageLoader(requester: requester),
            vision: vision,
            edits: edits,
            maxConcurrentRequests: maxConcurrentRequests
        )
    }

    /// A requester that answers every request at once with `image` (a small bitmap by default).
    private func respondingRequester(_ image: CGImage? = nil) throws -> MockImageRequester {
        let cgImage = try image ?? ImageTestSupport.makeImage()
        return MockImageRequester(
            defaultBehavior: .respond([ImageRequestResult(image: LoadedImage(cgImage: cgImage, orientation: .up))])
        )
    }

    // MARK: - Results

    /// A measurement carries the scoring version, Vision's signals and the edit flag; no faces stays `nil`.
    @Test func measuresSharpnessVisionSignalsAndEdits() async throws {
        let requester = try respondingRequester(SyntheticImages.pattern(0))
        let vision = MockQualityVisionExtractor(
            signature: 31,
            result: VisionQualityResult(faceQuality: nil, aesthetics: 0.25, isUtility: false)
        )
        let scorer = makeScorer(requester: requester, vision: vision, edits: MockAssetEditInspector(edited: ["a"]))

        let measurement = try #require(try await scorer.measure(asset("a")).measurement)

        #expect(scorer.scoringVersion == VisionQualityScorer.algorithmVersion * 1_000 + 31)
        #expect(measurement.version == scorer.scoringVersion)
        #expect(measurement.sharpness > 0)
        #expect(measurement.faceQuality == nil)
        #expect(measurement.aesthetics == 0.25)
        #expect(measurement.isUtility == false)
        #expect(measurement.isEdited)
        #expect(requester.requestedSizes == [ImageLoadingDefaults.targetSize])
    }

    /// The scoring version follows the Vision requests, so an OS update that adds aesthetics re-measures photos.
    @Test func theScoringVersionChangesWithTheVisionRequests() throws {
        let requester = try respondingRequester()
        let withoutAesthetics = makeScorer(requester: requester, vision: MockQualityVisionExtractor(signature: 30))
        let withAesthetics = makeScorer(requester: requester, vision: MockQualityVisionExtractor(signature: 31))
        #expect(withoutAesthetics.scoringVersion != withAesthetics.scoringVersion)
    }

    /// End to end with the real sharpness meter: the sharp photo measures sharper than its blurred copy.
    @Test func aSharpPhotoMeasuresSharperThanItsBlurredCopy() async throws {
        let sharp = try SyntheticImages.pattern(0)
        let blurred = try QualityTestImages.blurred(sharp, factor: 8)
        let sharpScore = try #require(
            try await makeScorer(requester: respondingRequester(sharp)).measure(asset("sharp")).measurement
        ).sharpness
        let blurredScore = try #require(
            try await makeScorer(requester: respondingRequester(blurred)).measure(asset("blurred")).measurement
        ).sharpness
        #expect(sharpScore > blurredScore)
    }

    /// Unloadable images are `.skipped` with their reason, and Vision never runs.
    @Test func imagesThatCannotBeLoadedAreSkippedWithoutRunningVision() async throws {
        let cases: [(MockImageRequester.Behavior, SkipReason)] = [
            (.respond([ImageRequestResult(isInCloud: true)]), .iCloudOnly),
            (.respond([ImageRequestResult()]), .decodeFailed),
            (.missing, .notFound)
        ]
        for (behavior, reason) in cases {
            let vision = MockQualityVisionExtractor()
            let scorer = makeScorer(requester: MockImageRequester(defaultBehavior: behavior), vision: vision)
            #expect(try await scorer.measure(asset("a")) == .skipped(reason))
            #expect(vision.callCount == 0)
        }
    }

    /// A photo deleted between loading and the edit check is skipped as not found.
    @Test func aPhotoGoneBeforeTheEditCheckIsSkipped() async throws {
        let scorer = makeScorer(
            requester: try respondingRequester(),
            edits: MockAssetEditInspector(missing: ["a"])
        )
        #expect(try await scorer.measure(asset("a")) == .skipped(.notFound))
    }

    /// A Vision error gives `.failed(.vision)`, and the next photo is still measured.
    @Test func aVisionErrorMarksThePhotoFailedAndTheNextOneIsStillMeasured() async throws {
        let vision = MockQualityVisionExtractor(failingCalls: [0])
        let scorer = makeScorer(requester: try respondingRequester(), vision: vision)
        #expect(try await scorer.measure(asset("a")) == .failed(.vision))
        #expect(try await scorer.measure(asset("b")).measurement != nil)
    }

    /// An image too small for the sharpness kernels fails instead of crashing.
    @Test func anImageTooSmallForSharpnessFails() async throws {
        let tiny = try QualityTestImages.flat(gray: 0.5, width: 2, height: 2)
        let scorer = makeScorer(requester: try respondingRequester(tiny))
        #expect(try await scorer.measure(asset("a")) == .failed(.vision))
    }

    // MARK: - Concurrency and cancellation

    /// Never more than `maxConcurrentRequests` measurements at once, and never on the main thread.
    @Test func limitsConcurrentMeasurementsAndStaysOffTheMainThread() async throws {
        let vision = MockQualityVisionExtractor(duration: 0.02)
        let scorer = makeScorer(requester: try respondingRequester(), vision: vision, maxConcurrentRequests: 2)
        try await withThrowingTaskGroup(of: QualityOutcome.self) { group in
            for index in 0..<8 {
                group.addTask { try await scorer.measure(asset("id\(index)")) }
            }
            for try await outcome in group {
                #expect(outcome.measurement != nil)
            }
        }
        #expect(vision.callCount == 8)
        #expect(vision.maxCallsAtOnce <= 2)
        #expect(vision.callsOnMainThread == 0)
    }

    /// A cancelled caller gets `CancellationError`, never a `.failed` photo.
    @Test func aCancelledCallerThrowsCancellation() async throws {
        let vision = MockQualityVisionExtractor()
        let scorer = makeScorer(requester: try respondingRequester(), vision: vision)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scorer.measure(asset("a"))
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(vision.callCount == 0)
    }

    // MARK: - Pieces

    /// No faces is `nil`, never 0; faces average their quality.
    @Test func faceQualityIsTheMeanOrNil() {
        #expect(VisionQualityExtractor.mean([]) == nil)
        #expect(VisionQualityExtractor.mean([.nan]) == nil)
        #expect(VisionQualityExtractor.mean([0.2, 0.6]) == 0.4)
    }

    /// The extractor's signature names the face revision and whether aesthetics run.
    @Test func theExtractorSignatureNamesRevisionAndAesthetics() {
        let without = VisionQualityExtractor(supportedFaceRevisions: [1, 2, 3], includesAesthetics: false)
        let with = VisionQualityExtractor(supportedFaceRevisions: [1, 2, 3], includesAesthetics: true)
        #expect(without.faceRevision == 3)
        #expect(without.signature == 30)
        #expect(with.signature == 31)
    }

    /// Adjustment data or a rendered full-size photo means the photo was edited.
    @Test func editsAreReadFromResourceTypes() {
        #expect(PhotoKitAssetEditInspector.isEdited(resourceTypes: [.photo, .adjustmentData]))
        #expect(PhotoKitAssetEditInspector.isEdited(resourceTypes: [.photo, .fullSizePhoto]))
        #expect(!PhotoKitAssetEditInspector.isEdited(resourceTypes: [.photo]))
        #expect(!PhotoKitAssetEditInspector.isEdited(resourceTypes: [.photo, .pairedVideo]))
    }
}

/// Thread-safe `QualityVisionExtracting` fake: returns a preset result, records calls and concurrency.
final class MockQualityVisionExtractor: QualityVisionExtracting, @unchecked Sendable {
    /// The error thrown by a failing call.
    struct VisionError: Error {}

    let signature: Int
    private let result: VisionQualityResult
    private let duration: TimeInterval
    private let failingCalls: Set<Int>
    private let lock = NSLock()
    private var calls = 0
    private var inFlight = 0
    private var maxInFlight = 0
    private var mainThreadCalls = 0

    init(
        signature: Int = 30,
        result: VisionQualityResult = VisionQualityResult(faceQuality: 0.5, aesthetics: nil, isUtility: nil),
        duration: TimeInterval = 0,
        failingCalls: Set<Int> = []
    ) {
        self.signature = signature
        self.result = result
        self.duration = duration
        self.failingCalls = failingCalls
    }

    var callCount: Int { lock.withLock { calls } }
    var maxCallsAtOnce: Int { lock.withLock { maxInFlight } }
    var callsOnMainThread: Int { lock.withLock { mainThreadCalls } }

    func analyze(_ image: LoadedImage) throws -> VisionQualityResult {
        let index = lock.withLock {
            defer { calls += 1 }
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            if Thread.isMainThread {
                mainThreadCalls += 1
            }
            return calls
        }
        defer { lock.withLock { inFlight -= 1 } }
        if duration > 0 {
            Thread.sleep(forTimeInterval: duration)
        }
        if failingCalls.contains(index) {
            throw VisionError()
        }
        return result
    }
}

/// `AssetEditInspecting` fake: edited and missing IDs are preset; everything else exists and is unedited.
struct MockAssetEditInspector: AssetEditInspecting {
    var edited: Set<String> = []
    var missing: Set<String> = []

    func isEdited(assetID: String) -> Bool? {
        missing.contains(assetID) ? nil : edited.contains(assetID)
    }
}
