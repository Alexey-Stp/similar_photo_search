import CoreGraphics
import Foundation
import Photos

/// Screen-size images for the comparison screen over `PHImageManager`, aspect-fit and local only.
///
/// - `.original` asks for one high-quality image resized **exactly** to the target size, so a 48 MP photo is never
///   decoded at full size. An original that is only in iCloud comes back empty with "in cloud" set.
/// - `.localPreview` asks `.opportunistic` for whatever PhotoKit has on the device (the high-quality local
///   thumbnail of an iCloud-only photo). It never downloads.
public final class PhotoKitScreenImageRequester: ImageRequesting, @unchecked Sendable {
    /// Which image to ask PhotoKit for.
    public enum Quality: Sendable {
        /// The original, decoded at the target size.
        case original
        /// The best image already on the device.
        case localPreview
    }

    /// Images keep their aspect ratio: the comparison never crops.
    public static let contentMode: PHImageContentMode = .aspectFit

    private let quality: Quality
    // `PHImageManager` is thread-safe; it is only stored and called.
    private let manager: PHImageManager

    /// Creates the requester over `PHImageManager.default()`.
    public init(quality: Quality) {
        self.quality = quality
        manager = PHImageManager.default()
    }

    /// The options for `quality`. Network access is never allowed.
    public static func makeOptions(for quality: Quality) -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        switch quality {
        case .original:
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
        case .localPreview:
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
        }
        options.version = .current
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        return options
    }

    /// Requests the image, or returns `nil` if no photo has `assetID`.
    public func requestImage(
        assetID: String,
        targetSize: CGSize,
        resultHandler: @escaping @Sendable (ImageRequestResult) -> Void
    ) -> ImageRequestID? {
        let options = Self.makeOptions(for: quality)
        return autoreleasepool { () -> ImageRequestID? in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                return nil
            }
            return manager.requestImage(
                for: asset,
                targetSize: PhotoKitScreenImageLoader.cappedSize(targetSize),
                contentMode: Self.contentMode,
                options: options
            ) { image, info in
                let result = autoreleasepool {
                    PhotoKitImageRequester.result(image: image, info: info)
                }
                resultHandler(result)
            }
        }
    }

    /// Cancels the PhotoKit request.
    public func cancelRequest(_ requestID: ImageRequestID) {
        manager.cancelImageRequest(requestID)
    }
}
