import Domain
import Foundation

/// What Home shows about the groups found: "12 groups of similar photos found", "38 photos in these groups",
/// "About 214 MB can be freed".
public struct HomeSummary: Sendable, Hashable {
    /// Number of groups.
    public let groupCount: Int
    /// Number of photos in all groups.
    public let photoCount: Int
    /// Estimated size of the photos currently selected for deletion, or `nil` while nothing is selected, the size is
    /// still being estimated or no size is known.
    public let reclaimableBytes: Int64?
    /// Whether `reclaimableBytes` is a lower bound because some sizes are unavailable.
    public let isLowerBound: Bool
    /// The photos the last scan left out.
    public let skipped: SkippedPhotosSummary

    /// Creates a summary.
    public init(
        groupCount: Int,
        photoCount: Int,
        reclaimableBytes: Int64? = nil,
        isLowerBound: Bool = false,
        skipped: SkippedPhotosSummary = SkippedPhotosSummary()
    ) {
        self.groupCount = groupCount
        self.photoCount = photoCount
        self.reclaimableBytes = reclaimableBytes
        self.isLowerBound = isLowerBound
        self.skipped = skipped
    }

    /// The summary of a selection store and the last scan's skips.
    @MainActor
    init(selection: SelectionStore, skipped: [SkipReason: Int]) {
        let photoCount = selection.clusterIDs.reduce(0) { total, id in
            total + (selection.state(for: id)?.memberIDs.count ?? 0)
        }
        let deletion = selection.summary
        let bytes = deletion.photoCount > 0 ? deletion.estimatedBytes : nil
        self.init(
            groupCount: selection.clusterIDs.count,
            photoCount: photoCount,
            reclaimableBytes: bytes,
            isLowerBound: bytes != nil && deletion.isLowerBound,
            skipped: SkippedPhotosSummary(counts: skipped)
        )
    }

    /// "About 214 MB can be freed", or `nil` when there is no size to show.
    public var reclaimableText: String? {
        guard let reclaimableBytes else { return nil }
        let size = reclaimableBytes.formatted(.byteCount(style: .file))
        if isLowerBound {
            return String(localized: "home.reclaimable.atLeast \(size)", bundle: .module)
        }
        return String(localized: "home.reclaimable \(size)", bundle: .module)
    }
}

/// The photos a scan left out, per reason, and the line Home shows for them.
public struct SkippedPhotosSummary: Sendable, Hashable {
    /// Skipped photos per reason; reasons with no photo are left out.
    public let counts: [SkipReason: Int]

    /// Creates a summary; zero and negative counts are dropped.
    public init(counts: [SkipReason: Int] = [:]) {
        self.counts = counts.filter { $0.value > 0 }
    }

    /// All skipped photos.
    public var total: Int {
        counts.values.reduce(0, +)
    }

    /// Whether any photo was skipped.
    public var isEmpty: Bool {
        counts.isEmpty
    }

    /// One reason and how many photos it left out.
    public struct Row: Sendable, Hashable, Identifiable {
        /// Why the photos were skipped.
        public let reason: SkipReason
        /// How many photos.
        public let count: Int

        /// The reason.
        public var id: SkipReason { reason }
    }

    /// The reasons with their counts, in `SkipReason.allCases` order.
    public var rows: [Row] {
        SkipReason.allCases.compactMap { reason in
            counts[reason].map { Row(reason: reason, count: $0) }
        }
    }

    /// "128 photos skipped (stored only in iCloud)" when every skip is iCloud-only, otherwise "130 photos skipped";
    /// `nil` when nothing was skipped.
    public var headline: String? {
        let total = total
        guard total > 0 else { return nil }
        if counts[.iCloudOnly] == total {
            return String(localized: "home.skipped.iCloud \(total)", bundle: .module)
        }
        return String(localized: "home.skipped \(total)", bundle: .module)
    }
}
