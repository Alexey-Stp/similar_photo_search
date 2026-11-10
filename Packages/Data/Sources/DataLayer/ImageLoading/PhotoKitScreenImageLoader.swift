import CoreGraphics
import Foundation

/// What the comparison screen gets for one photo.
public enum ScreenImageOutcome: Sendable {
    /// The original, decoded at screen size.
    case original(LoadedImage)
    /// The original is only in iCloud: the best local image instead (it is never downloaded).
    case localPreview(LoadedImage)
    /// Nothing to show: the photo is gone, could not be decoded, or the request was cancelled.
    case unavailable
}

/// Loads one photo at screen size for the comparison screen, local only.
///
/// Asks for the original first; when PhotoKit reports it is only in iCloud, asks for the local preview instead.
/// Cancelling the calling task cancels the PhotoKit request. Sizes are capped at `maxPixelSide` per side, so
/// nothing ever asks for `PHImageManagerMaximumSize`.
public struct PhotoKitScreenImageLoader: Sendable {
    /// The largest width or height ever requested, in pixels (above any iPhone or iPad screen).
    public static let maxPixelSide: CGFloat = 4_096

    private let original: any ImageRequesting
    private let preview: any ImageRequesting

    /// Creates the loader over `PHImageManager`.
    public init() {
        self.init(
            original: PhotoKitScreenImageRequester(quality: .original),
            preview: PhotoKitScreenImageRequester(quality: .localPreview)
        )
    }

    /// Creates the loader over any request API, for example fakes in tests.
    public init(original: any ImageRequesting, preview: any ImageRequesting) {
        self.original = original
        self.preview = preview
    }

    /// The photo at about `size` pixels (aspect fit), or its local preview when the original is in iCloud.
    public func screenImage(for assetID: String, size: CGSize) async -> ScreenImageOutcome {
        let size = Self.cappedSize(size)
        let full = await Self.collect(from: original, assetID: assetID, size: size)
        if let image = full.image {
            return .original(image)
        }
        guard full.isInCloud, !Task.isCancelled else { return .unavailable }
        let local = await Self.collect(from: preview, assetID: assetID, size: size)
        if let image = local.image {
            return .localPreview(image)
        }
        return .unavailable
    }

    /// `size` with each side between 1 and `maxPixelSide`; a negative or non-finite side (such as
    /// `PHImageManagerMaximumSize`) becomes `maxPixelSide`.
    public static func cappedSize(_ size: CGSize) -> CGSize {
        CGSize(width: cappedSide(size.width), height: cappedSide(size.height))
    }

    private static func cappedSide(_ side: CGFloat) -> CGFloat {
        guard side.isFinite, side > 0 else { return maxPixelSide }
        return min(maxPixelSide, max(1, side.rounded()))
    }

    /// Runs one request to its final callback and returns the last image it delivered.
    private static func collect(
        from requester: any ImageRequesting,
        assetID: String,
        size: CGSize
    ) async -> CollectedImage {
        let pending = PendingImageRequest(requester: requester)
        let collector = ImageCollector()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                collector.start(continuation)
                let requestID = requester.requestImage(assetID: assetID, targetSize: size) { result in
                    collector.receive(result)
                }
                if let requestID {
                    pending.attach(requestID)
                } else {
                    collector.finish()
                }
            }
        } onCancel: {
            pending.cancel()
            collector.cancel()
        }
    }
}

/// The outcome of one request.
private struct CollectedImage: Sendable {
    var image: LoadedImage?
    var isInCloud = false
}

/// Gathers the callbacks of one request and resumes the waiting task exactly once.
private final class ImageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CollectedImage, Never>?
    private var collected = CollectedImage()
    private var isFinished = false
    private var isCancelled = false

    /// Stores the continuation; resumes it at once if the task was already cancelled.
    func start(_ continuation: CheckedContinuation<CollectedImage, Never>) {
        lock.lock()
        self.continuation = continuation
        let cancelled = isCancelled
        lock.unlock()
        if cancelled {
            finish()
        }
    }

    /// Keeps the newest image; finishes on the final callback (not degraded), an error, a cancellation, or an
    /// empty "in cloud" answer.
    func receive(_ result: ImageRequestResult) {
        lock.lock()
        if result.isInCloud {
            collected.isInCloud = true
        }
        if let image = result.image, !result.isCancelled, !isCancelled {
            collected.image = image
        }
        let isFinal = !result.isDegraded || result.isCancelled || result.hasError
            || (result.isInCloud && result.image == nil)
        lock.unlock()
        if isFinal {
            finish()
        }
    }

    /// The task was cancelled: drop any image and finish.
    func cancel() {
        lock.lock()
        isCancelled = true
        collected.image = nil
        lock.unlock()
        finish()
    }

    /// Resumes the waiting task once.
    func finish() {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        var result = collected
        if isCancelled {
            result.image = nil
        }
        lock.unlock()
        continuation.resume(returning: result)
    }
}
