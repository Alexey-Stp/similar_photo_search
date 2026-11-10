import CoreGraphics
import Foundation
import ImageIO
import Photos
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// `ImageRequesting` over `PHImageManager`: the only place that touches `PHAsset` and platform images for analysis.
///
/// Images are requested local-only (network access is never allowed), so iCloud-only originals come back as
/// "in cloud" and are skipped, never downloaded. Each callback converts the platform image to a `CGImage` inside an
/// `autoreleasepool`, so the platform image is released before the result leaves this type.
public final class PhotoKitImageRequester: ImageRequesting, @unchecked Sendable {
    /// Analysis images keep their aspect ratio and fit inside the target size.
    public static let contentMode: PHImageContentMode = .aspectFit

    // `PHImageManager` is thread-safe; it is only stored and called.
    private let manager: PHImageManager

    /// Creates the requester over `PHImageManager.default()`.
    public init() {
        manager = PHImageManager.default()
    }

    /// The options for every analysis request: one high-quality callback, fast resizing, current version, no network.
    public static func makeOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.version = .current
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        return options
    }

    /// Fetches the asset by identifier and requests its image, or returns `nil` if the asset doesn't exist.
    public func requestImage(
        assetID: String,
        targetSize: CGSize,
        resultHandler: @escaping @Sendable (ImageRequestResult) -> Void
    ) -> ImageRequestID? {
        // The lookup and request setup create autoreleased PhotoKit objects; drain them here, because Swift
        // concurrency's worker threads don't reliably do it.
        autoreleasepool { () -> ImageRequestID? in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                return nil
            }
            return manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: Self.contentMode,
                options: Self.makeOptions()
            ) { image, info in
                let result = autoreleasepool {
                    Self.result(image: image, info: info)
                }
                resultHandler(result)
            }
        }
    }

    /// Cancels the PhotoKit request.
    public func cancelRequest(_ requestID: ImageRequestID) {
        manager.cancelImageRequest(requestID)
    }

    /// Reduces a PhotoKit callback to `Sendable` values. Shared with `PhotoKitThumbnailRequester`.
    static func result(image: PlatformImage?, info: [AnyHashable: Any]?) -> ImageRequestResult {
        ImageRequestResult(
            image: image.flatMap(loadedImage(from:)),
            isInCloud: (info?[PHImageResultIsInCloudKey] as? Bool) ?? false,
            isCancelled: (info?[PHImageCancelledKey] as? Bool) ?? false,
            isDegraded: (info?[PHImageResultIsDegradedKey] as? Bool) ?? false,
            hasError: info?[PHImageErrorKey] != nil
        )
    }

    #if canImport(UIKit)
    typealias PlatformImage = UIImage

    /// The image's pixels and orientation, or `nil` if it has no bitmap.
    private static func loadedImage(from image: UIImage) -> LoadedImage? {
        guard let cgImage = image.cgImage else { return nil }
        return LoadedImage(cgImage: cgImage, orientation: orientation(of: image.imageOrientation))
    }

    /// The `CGImagePropertyOrientation` (what Vision expects) for a `UIImage.Orientation`.
    public static func orientation(of orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:
            .up
        case .upMirrored:
            .upMirrored
        case .down:
            .down
        case .downMirrored:
            .downMirrored
        case .left:
            .left
        case .leftMirrored:
            .leftMirrored
        case .right:
            .right
        case .rightMirrored:
            .rightMirrored
        @unknown default:
            .up
        }
    }
    #else
    typealias PlatformImage = NSImage

    /// The image's pixels; on macOS PhotoKit returns images already upright.
    private static func loadedImage(from image: NSImage) -> LoadedImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return LoadedImage(cgImage: cgImage, orientation: .up)
    }
    #endif
}
