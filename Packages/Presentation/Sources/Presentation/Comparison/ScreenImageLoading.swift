import CoreGraphics
import Foundation

/// One photo at screen size for the comparison screen.
public struct ScreenImage: Sendable {
    /// The pixels and their orientation.
    public let image: Thumbnail
    /// Whether the original is only in iCloud and `image` is the local preview instead ("Original in iCloud").
    public let isOriginalInCloud: Bool

    /// Creates a screen image.
    public init(image: Thumbnail, isOriginalInCloud: Bool) {
        self.image = image
        self.isOriginalInCloud = isOriginalInCloud
    }
}

/// Loads photos at screen size for the comparison screen, local only.
///
/// The app implements it over `PHImageManager` (aspect fit, `isNetworkAccessAllowed = false`, never the maximum
/// size); previews and tests use fakes. Sizes are in **pixels** (view size × display scale).
public protocol ScreenImageLoading: Sendable {
    /// The photo at about `pixelSize` (aspect fit): the original, or the high-quality local preview when the
    /// original is only in iCloud. `nil` if the photo is gone, can't be decoded, or the task was cancelled
    /// (cancelling the task cancels the request).
    func screenImage(for assetID: String, pixelSize: CGSize) async -> ScreenImage?
}
