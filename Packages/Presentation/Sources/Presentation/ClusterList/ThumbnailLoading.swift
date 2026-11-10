import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// A decoded thumbnail with the orientation to show it upright.
///
/// `CGImage` is immutable and thread-safe, so the value can cross actors. Hold it only while a cell shows it.
public struct Thumbnail: @unchecked Sendable {
    /// The pixels, not rotated.
    public let cgImage: CGImage
    /// How SwiftUI must rotate or mirror the pixels.
    public let orientation: Image.Orientation

    /// Creates a thumbnail from pixels and their EXIF orientation (what PhotoKit reports).
    public init(cgImage: CGImage, exifOrientation: CGImagePropertyOrientation) {
        self.cgImage = cgImage
        orientation = Self.orientation(of: exifOrientation)
    }

    /// The SwiftUI orientation for an EXIF orientation.
    static func orientation(of exif: CGImagePropertyOrientation) -> Image.Orientation {
        switch exif {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// Loads small, local-only thumbnails for the group list and keeps a bounded prefetch window warm.
///
/// The app implements it over `PHCachingImageManager` (`.opportunistic`, never the network); previews and tests use
/// fakes. Sizes are in **pixels** (display size × display scale).
public protocol ThumbnailLoading: Sendable {
    /// The thumbnail of one photo: possibly a degraded image first, then the final one. The stream finishes after
    /// the final image, or without any image if the photo is gone or has no local data. Ending the consuming task
    /// (the cell left the screen) cancels the request.
    func thumbnail(for assetID: String, pixelSize: CGSize) -> AsyncStream<Thumbnail>

    /// Starts caching thumbnails of photos about to scroll into view. The implementation bounds how many it keeps.
    func prefetch(_ assetIDs: [String], pixelSize: CGSize) async

    /// Stops caching thumbnails of photos that left the prefetch window.
    func stopPrefetching(_ assetIDs: [String], pixelSize: CGSize) async

    /// Drops every cached thumbnail, for example when the list closes.
    func stopAllPrefetching() async
}
