import Foundation

/// What would be deleted right now: "38 photos, about 214 MB will be deleted".
///
/// Sizes are estimates (from undocumented PhotoKit metadata), so the text always says "about" or "at least".
public struct DeletionSummary: Sendable, Hashable {
    /// Number of photos selected for deletion.
    public let photoCount: Int
    /// Sum of the sizes that are known, in bytes.
    public let knownBytes: Int64
    /// Selected photos whose size is unavailable.
    public let unavailableCount: Int
    /// Selected photos whose size is still being estimated.
    public let pendingCount: Int

    /// Creates a summary.
    public init(photoCount: Int, knownBytes: Int64, unavailableCount: Int, pendingCount: Int) {
        self.photoCount = photoCount
        self.knownBytes = knownBytes
        self.unavailableCount = unavailableCount
        self.pendingCount = pendingCount
    }

    /// Nothing selected.
    public static let empty = DeletionSummary(photoCount: 0, knownBytes: 0, unavailableCount: 0, pendingCount: 0)

    /// Whether sizes are still being estimated.
    public var isEstimating: Bool { pendingCount > 0 }

    /// The estimated size in bytes, or `nil` while estimating or when no size is available at all.
    public var estimatedBytes: Int64? {
        guard !isEstimating, unavailableCount < photoCount else { return nil }
        return knownBytes
    }

    /// Whether `estimatedBytes` is a lower bound because some sizes are unavailable.
    public var isLowerBound: Bool { unavailableCount > 0 }

    /// The localized sentence shown before deletion.
    public var text: String {
        if photoCount == 0 {
            return String(localized: "selection.summary.none", bundle: .module)
        }
        if isEstimating {
            return String(localized: "selection.summary.estimating \(photoCount)", bundle: .module)
        }
        guard let bytes = estimatedBytes else {
            return String(localized: "selection.summary.sizeUnavailable \(photoCount)", bundle: .module)
        }
        let size = bytes.formatted(.byteCount(style: .file))
        if isLowerBound {
            return String(localized: "selection.summary.atLeast \(photoCount) \(size)", bundle: .module)
        }
        return String(localized: "selection.summary \(photoCount) \(size)", bundle: .module)
    }
}
