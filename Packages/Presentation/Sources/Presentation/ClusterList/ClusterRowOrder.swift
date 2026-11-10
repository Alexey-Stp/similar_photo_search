import Foundation

/// The order of the group rows in the list: append-only, with one exception for groups newer than every row.
///
/// A scan publishes sessions newest first and re-publishes **every** current group, under the same IDs. So within one
/// scan, a group that is new to the list and arrives *before* the scan re-published any row already shown is newer
/// than every row (the live observer found new photos): it is inserted above them, in arrival order. Every other new
/// group is appended at the end (the scan's normal order: new results are older photos). Rows never move otherwise.
public struct ClusterRowOrder: Sendable, Hashable {
    /// Cluster IDs, top row first.
    public private(set) var ids: [String] = []

    private var known: Set<String> = []
    /// Where the next new group goes while the running scan has not re-published a row yet; `nil` means append.
    private var topInsertionIndex: Int?

    /// Creates an empty order.
    public init() {}

    /// A scan started. Until it re-publishes a row already shown, its new groups are newer than every row.
    public mutating func scanStarted() {
        topInsertionIndex = ids.isEmpty ? nil : 0
    }

    /// Places groups in the order the scan published them. IDs already shown keep their row.
    public mutating func add(_ clusterIDs: [String]) {
        for id in clusterIDs {
            guard known.insert(id).inserted else {
                // The scan reached the rows already shown: everything after this is older.
                topInsertionIndex = nil
                continue
            }
            if let index = topInsertionIndex {
                ids.insert(id, at: index)
                topInsertionIndex = index + 1
            } else {
                ids.append(id)
            }
        }
    }

    /// Removes rows. Unknown IDs are ignored.
    public mutating func remove(_ clusterIDs: some Sequence<String>) {
        let removed = Set(clusterIDs).intersection(known)
        guard !removed.isEmpty else { return }
        if let index = topInsertionIndex {
            topInsertionIndex = index - ids[..<index].filter { removed.contains($0) }.count
        }
        ids.removeAll { removed.contains($0) }
        known.subtract(removed)
    }
}
