import CoreGraphics
import SwiftUI

/// Pure layout rules of the comparison screen.
public enum ComparisonLayout {
    /// The largest width or height ever requested for a screen image, in pixels.
    public static let maxPixelSide: CGFloat = 4_096

    /// The pixel size to request for a view of `points` on a screen of `scale`: whole pixels, each side between 1
    /// and `maxPixelSide`, so a photo is never decoded at its original size.
    public static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        return CGSize(width: side(points.width * scale), height: side(points.height * scale))
    }

    /// Whether the two-up mode fits: a regular width (iPad) or a compact height (iPhone in landscape).
    public static func canShowSideBySide(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> Bool {
        horizontal == .regular || vertical == .compact
    }

    /// The size an image of `imageSize` takes when it fits inside `container` without cropping.
    public static func fittedSize(of imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let factor = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
    }

    /// One side in whole pixels between 1 and `maxPixelSide`; anything not positive becomes 1.
    private static func side(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        return min(maxPixelSide, max(1, value.rounded()))
    }
}

extension Thumbnail {
    /// The size of the image as shown upright (width and height swapped for rotated orientations).
    var uprightSize: CGSize {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}
