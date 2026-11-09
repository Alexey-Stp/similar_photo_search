import CoreGraphics
import Domain
import Foundation
import os

/// `FeaturePrintService` over Vision: loads a downscaled image (`ImageLoading`) and extracts its feature print.
///
/// Vision is synchronous, so extraction runs on a private dispatch queue, never on the main thread and never blocking
/// a Swift-concurrency thread. At most `maxConcurrentRequests` Vision requests run at a time (2 by default), however
/// many callers there are. Holds no images: each one lives only for its own call.
public struct VisionFeaturePrintService: FeaturePrintService {
    /// Vision requests allowed in flight at the same time by default.
    public static let defaultMaxConcurrentRequests = 2

    private static let logger = Logger(subsystem: "com.similarphotos", category: "featurePrints")
    private static let visionQueue = DispatchQueue(
        label: "com.similarphotos.vision.featurePrints",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let images: any ImageLoading
    private let extractor: any FeaturePrintExtracting
    private let limiter: ConcurrencyLimiter
    private let targetSize: CGSize

    /// The revision of the extractor, which every computed print carries.
    public var revision: Int { extractor.revision }

    /// Creates the service with the Vision extractor.
    public init(
        images: any ImageLoading,
        maxConcurrentRequests: Int = VisionFeaturePrintService.defaultMaxConcurrentRequests
    ) {
        self.init(
            images: images,
            extractor: VisionFeaturePrintExtractor(),
            maxConcurrentRequests: maxConcurrentRequests
        )
    }

    /// Creates the service with any extractor, for example a mock in tests.
    /// - Parameters:
    ///   - maxConcurrentRequests: Extractions allowed at the same time; values below 1 are treated as 1.
    ///   - targetSize: Size of the analysis image; `ImageLoadingDefaults.targetSize` (512 px) by default.
    public init(
        images: any ImageLoading,
        extractor: any FeaturePrintExtracting,
        maxConcurrentRequests: Int = VisionFeaturePrintService.defaultMaxConcurrentRequests,
        targetSize: CGSize = ImageLoadingDefaults.targetSize
    ) {
        self.images = images
        self.extractor = extractor
        self.limiter = ConcurrencyLimiter(limit: maxConcurrentRequests)
        self.targetSize = targetSize
    }

    /// Loads the photo's analysis image and computes its print; see `FeaturePrintService.featurePrint(for:)`.
    public func featurePrint(for asset: PhotoAsset) async throws -> FeaturePrintOutcome {
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
        let result: Result<ExtractedFeaturePrint, any Error>
        if Task.isCancelled {
            result = .failure(CancellationError())
        } else {
            result = await extractOffThread(image)
        }
        await limiter.release()

        // A print finished before a cancellation is still valid and worth saving, but a failure during a cancelled scan
        // must not mark the photo as failed.
        if case .failure = result {
            try Task.checkCancellation()
        }

        switch result {
        case .success(let extracted):
            return .computed(FeaturePrint(
                assetID: asset.id,
                revision: extracted.revision,
                vector: extracted.vector,
                assetModificationDate: asset.modificationDate
            ))
        case .failure(let error as CancellationError):
            throw error
        case .failure(let error):
            Self.logger.error("""
                Feature print failed for \(asset.id, privacy: .private): \
                \(String(describing: error), privacy: .public)
                """)
            return .failed(.vision)
        }
    }

    /// Runs the synchronous extractor on the Vision queue.
    private func extractOffThread(_ image: LoadedImage) async -> Result<ExtractedFeaturePrint, any Error> {
        let extractor = self.extractor
        return await withCheckedContinuation { continuation in
            Self.visionQueue.async {
                do {
                    continuation.resume(returning: .success(try extractor.extract(from: image)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
    }
}
