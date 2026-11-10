import Domain
import Foundation

/// What the info panel shows about one photo, apart from its keep / delete choice.
public struct ComparisonPhotoInfo: Hashable, Sendable {
    /// When the photo was taken, if known.
    public var date: Date?
    /// Width of the original in pixels, 0 while unknown.
    public var pixelWidth = 0
    /// Height of the original in pixels, 0 while unknown.
    public var pixelHeight = 0
    /// The size of all its files, `nil` while unknown or unavailable.
    public var fileSize: Int64?
    /// Whether the user marked it as a favorite.
    public var isFavorite = false
    /// Whether it has edits.
    public var isEdited = false
    /// Whether it is a Live Photo.
    public var isLivePhoto = false
    /// Why it ranks well ("Sharpest", "Best faces"), best reason first; empty when it was not ranked.
    public var reasons: [QualityReason] = []

    /// Creates an empty info.
    public init() {}

    /// "4032 × 3024 · 12.2 MP", or `nil` while the resolution is unknown.
    public var resolutionText: String? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let megapixels = Double(pixelWidth * pixelHeight) / 1_000_000
        let mpText = megapixels.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "compare.info.resolution \(pixelWidth) \(pixelHeight) \(mpText)", bundle: .module)
    }

    /// "3.2 MB", or `nil` while the size is unknown or unavailable.
    public var fileSizeText: String? {
        fileSize.map { $0.formatted(.byteCount(style: .file)) }
    }

    /// The localized text of each reason.
    public var reasonTexts: [String] {
        reasons.map { Bundle.module.localizedString(forKey: $0.rawValue, value: nil, table: nil) }
    }
}
