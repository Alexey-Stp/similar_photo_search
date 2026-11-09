import Foundation

/// Why a photo was left out of analysis. Skipped photos are counted per reason in the scan summary.
public enum SkipReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// The original is only in iCloud. The app never downloads, so it can't analyse the photo.
    case iCloudOnly
    /// The image exists but couldn't be decoded (for example a corrupt file).
    case decodeFailed
    /// The photo no longer exists, for example because it was deleted after it was listed.
    case notFound
    /// The photo has no `creationDate`, so it belongs to no shooting session and is never compared.
    /// Counted by `SessionSegmentationSummary.skippedNoDateCount`.
    case noDate
}
