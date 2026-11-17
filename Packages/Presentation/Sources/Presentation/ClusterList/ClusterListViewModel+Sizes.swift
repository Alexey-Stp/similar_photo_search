import Domain
import Foundation

/// File sizes of the photos in groups, from the estimates loaded so far: everything, and what is selected for
/// deletion.
public struct GroupSizes: Hashable, Sendable {
    /// The size of every photo whose size is known, in bytes.
    public var totalBytes: Int64
    /// The size of the selected photos whose size is known, in bytes.
    public var selectedBytes: Int64
    /// Whether every photo's size has been looked up (unavailable sizes count as looked up).
    public var isComplete: Bool

    /// No photos.
    public static let zero = GroupSizes(totalBytes: 0, selectedBytes: 0, isComplete: true)

    /// Creates sizes.
    public init(totalBytes: Int64, selectedBytes: Int64, isComplete: Bool) {
        self.totalBytes = totalBytes
        self.selectedBytes = selectedBytes
        self.isComplete = isComplete
    }
}

extension ClusterListViewModel {
    /// The sizes of one group, or `nil` if the group is gone. Updates as sizes arrive and photos are toggled.
    public func sizes(of clusterID: String) -> GroupSizes? {
        _ = sizesRevision
        guard let state = selection.state(for: clusterID) else { return nil }
        var sizes = GroupSizes.zero
        for id in state.memberIDs {
            if let size = memberSizes[id] {
                sizes.totalBytes += size
                if state.isSelected(id) {
                    sizes.selectedBytes += size
                }
            } else if !unavailableSizes.contains(id) {
                sizes.isComplete = false
            }
        }
        return sizes
    }

    /// The sizes of every group together: the size of all photos in groups and of those selected for deletion.
    public var allGroupsSizes: GroupSizes {
        selection.clusterIDs.reduce(into: GroupSizes.zero) { result, clusterID in
            guard let sizes = sizes(of: clusterID) else { return }
            result.totalBytes += sizes.totalBytes
            result.selectedBytes += sizes.selectedBytes
            result.isComplete = result.isComplete && sizes.isComplete
        }
    }
}
