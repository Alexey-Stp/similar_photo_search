import Foundation

extension PhotoSession {
    /// The newest photo's `creationDate` read back from a session ID made by `id(newestID:newestDate:)`, to the
    /// millisecond. `nil` if the ID has no `"@<milliseconds>"` suffix.
    public static func newestDate(fromID id: String) -> Date? {
        guard let separator = id.lastIndex(of: "@"),
              let milliseconds = Int64(id[id.index(after: separator)...]) else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
}

extension StoredSessionResult {
    /// The newest photo's date of the session, from its ID; `nil` for an ID without a date.
    public var newestDate: Date? {
        PhotoSession.newestDate(fromID: sessionID)
    }

    /// The stored clusters as they are shown at launch, before the next scan has re-published them.
    ///
    /// - Sessions newest first (as a scan publishes them), equal dates by session ID, sessions without a readable
    ///   date last; clusters in their stored order.
    /// - No suggestion: every photo is kept (`ClusterSelection(unsuggested:)`). The next scan re-publishes the same
    ///   IDs with a suggestion, which replaces these in place.
    /// - A cluster ID appears once (the first, newest one wins).
    public static func launchSelections(from results: [StoredSessionResult]) -> [ClusterSelection] {
        let ordered = results
            .map { (date: $0.newestDate, result: $0) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.result.sessionID < rhs.result.sessionID
                }
            }
        var seen = Set<String>()
        var selections: [ClusterSelection] = []
        for entry in ordered {
            for cluster in entry.result.clusters where seen.insert(cluster.id).inserted {
                selections.append(ClusterSelection(unsuggested: cluster))
            }
        }
        return selections
    }
}

extension ClusterSelection {
    /// A cluster without a Smart Selection suggestion: no keeper, nothing pre-selected, not flagged for review.
    /// Used for stored clusters shown before a scan has ranked them.
    public init(unsuggested cluster: SimilarityCluster) {
        self.init(
            cluster: cluster.withKeeper(nil),
            ranking: [],
            suggestedForDeletion: [],
            needsReview: false
        )
    }
}
