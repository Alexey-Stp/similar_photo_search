import CoreGraphics
import Domain
import Foundation
import os

/// `QualityScorer` over Vision and vImage: loads a downscaled image (`ImageLoading`), then measures sharpness (variance
/// of the Laplacian), face capture quality and, on iOS 18, aesthetics, and reads whether the photo has edits.
///
/// The work is synchronous, so it runs on a private dispatch queue, never on the main thread and never blocking a
/// Swift-concurrency thread. At most `maxConcurrentRequests` measurements run at a time (2 by default). Holds no
/// images: each one lives only for its own call.
public struct VisionQualityScorer: QualityScorer {
    /// Bump when the measurement changes (for example the sharpness kernels or the image size), so cached
    /// measurements are made again.
    public static let algorithmVersion = 1
    /// Measurements allowed in flight at the same time by default.
    public static let defaultMaxConcurrentRequests = 2

    private static let logger = Logger(subsystem: "com.similarphotos", category: "quality")
    private static let workQueue = DispatchQueue(
        label: "com.similarphotos.vision.quality",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let images: any ImageLoading
    private let vision: any QualityVisionExtracting
    private let edits: any AssetEditInspecting
    private let sharpnessMeter = SharpnessMeter()
    private let limiter: ConcurrencyLimiter
    private let targetSize: CGSize

    /// `algorithmVersion * 1000 + vision.signature`: changes with the algorithm and with the Vision requests this OS
    /// offers, so a measurement made before an iOS update that added aesthetics is made again.
    public var scoringVersion: Int { Self.algorithmVersion * 1_000 + vision.signature }

    /// Creates the scorer with the Vision extractor for this OS.
    public init(
        images: any ImageLoading,
        edits: any AssetEditInspecting,
        maxConcurrentRequests: Int = VisionQualityScorer.defaultMaxConcurrentRequests
    ) {
        self.init(
            images: images,
            vision: VisionQualityExtractor(),
            edits: edits,
            maxConcurrentRequests: maxConcurrentRequests
        )
    }

    /// Creates the scorer with any Vision extractor, for example a mock in tests.
    /// - Parameters:
    ///   - maxConcurrentRequests: Measurements allowed at the same time; values below 1 are treated as 1.
    ///   - targetSize: Size of the analysis image; `ImageLoadingDefaults.targetSize` (512 px) by default.
    public init(
        images: any ImageLoading,
        vision: any QualityVisionExtracting,
        edits: any AssetEditInspecting,
        maxConcurrentRequests: Int = VisionQualityScorer.defaultMaxConcurrentRequests,
        targetSize: CGSize = ImageLoadingDefaults.targetSize
    ) {
        self.images = images
        self.vision = vision
        self.edits = edits
        self.limiter = ConcurrencyLimiter(limit: maxConcurrentRequests)
        self.targetSize = targetSize
    }

    /// Loads the photo's analysis image and measures it; see `QualityScorer.measure(_:)`.
    public func measure(_ asset: PhotoAsset) async throws -> QualityOutcome {
        let image: LoadedImage
        do {
            image = try await images.loadImage(assetID: asset.id, targetSize: targetSize)
        } catch {
            try Task.checkCancellation()
            guard let loadError = error as? ImageLoadError else {
                return .skipped(.decodeFailed)
            }
            guard let reason = loadError.skipReason else {
                throw CancellationError()
            }
            return .skipped(reason)
        }

        try await limiter.acquire()
        let result: Result<QualityMeasurement?, any Error>
        if Task.isCancelled {
            result = .failure(CancellationError())
        } else {
            result = await measureOffThread(image, assetID: asset.id)
        }
        await limiter.release()

        // A measurement finished before a cancellation is still valid; a failure during a cancelled scan is not one.
        if case .failure = result {
            try Task.checkCancellation()
        }

        switch result {
        case .success(let measurement?):
            return .measured(measurement)
        case .success(nil):
            return .skipped(.notFound)
        case .failure(let error as CancellationError):
            throw error
        case .failure(let error):
            Self.logger.error("""
                Quality measurement failed for \(asset.id, privacy: .private): \
                \(String(describing: error), privacy: .public)
                """)
            return .failed(.vision)
        }
    }

    /// Measures a loaded image: sharpness, Vision signals and the edit flag. `nil` if the photo no longer exists.
    ///
    /// Synchronous: call it off the main thread. Runs inside one `autoreleasepool`.
    func measurement(of image: LoadedImage, assetID: String) throws -> QualityMeasurement? {
        try autoreleasepool {
            let sharpness = try sharpnessMeter.sharpness(of: image.cgImage)
            let visionResult = try vision.analyze(image)
            guard let isEdited = edits.isEdited(assetID: assetID) else { return nil }
            return QualityMeasurement(
                version: scoringVersion,
                sharpness: sharpness,
                faceQuality: visionResult.faceQuality,
                aesthetics: visionResult.aesthetics,
                isUtility: visionResult.isUtility,
                isEdited: isEdited
            )
        }
    }

    /// Runs `measurement(of:assetID:)` on the work queue.
    private func measureOffThread(
        _ image: LoadedImage,
        assetID: String
    ) async -> Result<QualityMeasurement?, any Error> {
        await withCheckedContinuation { continuation in
            Self.workQueue.async {
                do {
                    continuation.resume(returning: .success(try measurement(of: image, assetID: assetID)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
}
