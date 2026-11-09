import CoreGraphics
import Domain
import Foundation
import ImageIO

/// A downscaled image for analysis, with the orientation Vision needs to read it upright.
///
/// `CGImage` is immutable and thread-safe, so the value can cross actors. Keep it only as long as one analysis
/// step needs it: never collect these in arrays (CLAUDE.md, memory discipline).
public struct LoadedImage: @unchecked Sendable {
    /// The pixels, not rotated: pass `orientation` along to Vision.
    public let cgImage: CGImage
    /// How the pixels must be rotated or mirrored to show the photo upright.
    public let orientation: CGImagePropertyOrientation

    /// Creates a loaded image.
    public init(cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

/// Why an image could not be loaded.
public enum ImageLoadError: Error, Sendable, Hashable {
    /// No photo has this identifier (deleted since it was listed).
    case notFound
    /// The original is only in iCloud. Network access is never allowed, so the photo is skipped.
    case iCloudOnly
    /// PhotoKit returned no usable image, for example for a corrupt file.
    case decodeFailed
    /// The request was cancelled because the calling task was cancelled.
    case cancelled

    /// The reason to count in the scan summary, or `nil` for a cancellation (which is not a skip).
    public var skipReason: SkipReason? {
        switch self {
        case .notFound:
            .notFound
        case .iCloudOnly:
            .iCloudOnly
        case .decodeFailed:
            .decodeFailed
        case .cancelled:
            nil
        }
    }
}

/// The result of loading one photo in a batch.
public struct ImageLoadOutcome: Sendable {
    /// The photo's local identifier.
    public let assetID: String
    /// The image, or why it couldn't be loaded.
    public let result: Result<LoadedImage, ImageLoadError>

    /// Creates an outcome.
    public init(assetID: String, result: Result<LoadedImage, ImageLoadError>) {
        self.assetID = assetID
        self.result = result
    }
}

/// Loads downscaled images for analysis. Never uses the network.
///
/// Lives in Data, not Domain: Domain never sees an image. The Vision services load images through this protocol
/// and hand Domain only values (a `FeaturePrint`, a score, a `SkipReason`).
public protocol ImageLoading: Sendable {
    /// Loads one photo at about `targetSize` pixels (aspect fit).
    /// - Throws: `ImageLoadError`. A cancelled calling task throws `ImageLoadError.cancelled`.
    func loadImage(assetID: String, targetSize: CGSize) async throws -> LoadedImage

    /// Loads several photos with at most `maxConcurrent` requests in flight. Values below 1 are treated as 1 (as
    /// `pageSize` is in `PhotoLibraryRepository`); to pause, don't call this.
    ///
    /// Outcomes arrive in completion order, one per identifier; a failed photo never stops the batch. Loading only runs
    /// ahead of the consumer by `maxConcurrent` images, so memory stays flat however slowly the outcomes are used.
    /// Cancelling the consuming task, or dropping the stream before it ends, cancels the pending PhotoKit requests.
    func loadBatch(_ assetIDs: [String], targetSize: CGSize, maxConcurrent: Int) -> AsyncStream<ImageLoadOutcome>
}

/// Default sizes and limits for analysis images.
public enum ImageLoadingDefaults {
    /// Analysis images are about 512 px on their longer side.
    public static let targetSize = CGSize(width: 512, height: 512)

    /// At most four requests in flight, fewer on devices with fewer active cores.
    public static var maxConcurrent: Int {
        min(4, ProcessInfo.processInfo.activeProcessorCount)
    }
}

extension ImageLoading {
    /// Loads several photos at the default size and concurrency.
    public func loadBatch(_ assetIDs: [String]) -> AsyncStream<ImageLoadOutcome> {
        loadBatch(
            assetIDs,
            targetSize: ImageLoadingDefaults.targetSize,
            maxConcurrent: ImageLoadingDefaults.maxConcurrent
        )
    }
}

/// Identifies an in-flight image request so it can be cancelled (`PHImageRequestID`).
public typealias ImageRequestID = Int32

/// What one image-request callback reported, already reduced to `Sendable` values.
public struct ImageRequestResult: Sendable {
    /// The decoded image, if PhotoKit returned one.
    public var image: LoadedImage?
    /// `PHImageResultIsInCloudKey`: the full-quality data is only in iCloud.
    public var isInCloud: Bool
    /// `PHImageCancelledKey`: the request was cancelled.
    public var isCancelled: Bool
    /// `PHImageResultIsDegradedKey`: a low-quality stand-in rather than the requested image.
    public var isDegraded: Bool
    /// `PHImageErrorKey` was set.
    public var hasError: Bool

    /// Creates a result.
    public init(
        image: LoadedImage? = nil,
        isInCloud: Bool = false,
        isCancelled: Bool = false,
        isDegraded: Bool = false,
        hasError: Bool = false
    ) {
        self.image = image
        self.isInCloud = isInCloud
        self.isCancelled = isCancelled
        self.isDegraded = isDegraded
        self.hasError = hasError
    }
}

/// The callback-based image API under `PhotoKitImageLoader`: `PHImageManager` in the app, a mock in tests.
public protocol ImageRequesting: Sendable {
    /// Starts a request and returns its ID, or returns `nil` without calling `resultHandler` if no photo has `assetID`.
    /// `resultHandler` may be called on any thread, before or after this method returns, and possibly more than once.
    func requestImage(
        assetID: String,
        targetSize: CGSize,
        resultHandler: @escaping @Sendable (ImageRequestResult) -> Void
    ) -> ImageRequestID?

    /// Cancels an in-flight request. Calling it for a finished request does nothing.
    func cancelRequest(_ requestID: ImageRequestID)
}
