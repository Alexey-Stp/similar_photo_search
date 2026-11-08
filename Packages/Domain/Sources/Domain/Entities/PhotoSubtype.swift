import Foundation

/// Media subtypes of a photo that matter for grouping and keeper selection.
///
/// Mirrors the relevant `PHAssetMediaSubtype` flags without depending on PhotoKit.
public enum PhotoSubtype: String, Sendable, Hashable, CaseIterable {
    /// A screenshot taken on the device.
    case screenshot
    /// A high dynamic range photo.
    case hdr
    /// A panorama.
    case panorama
    /// A Live Photo.
    case livePhoto
    /// A photo with a depth effect (Portrait mode).
    case depthEffect
}
