import Foundation

extension ClusterSelection {
    /// The suggestion for the same cluster after `removed` photos were deleted, recomputed locally without new
    /// measurements; `nil` when fewer than two members are left (a group of one is not a group).
    ///
    /// - Members, ranking and the suggestion keep only the survivors. Distance and the exact-duplicate flag are kept
    ///   (the vectors are not at hand).
    /// - The cluster keeps its ID unless that photo was deleted; then the ID is the newest survivor, the ID a scan
    ///   gives the shrunk cluster (`SimilarityCluster`'s default), so a later re-publish matches it.
    /// - A surviving keeper stays the keeper. Otherwise the best-ranked survivor becomes the keeper, it is kept, and
    ///   the cluster is flagged `needsReview`: the scores were normalized with the deleted photos, so the next scan's
    ///   suggestion may differ. Without a ranked survivor there is no keeper and nothing is suggested.
    /// - Returns `self` when no member was removed.
    public func removingMembers(_ removed: Set<String>) -> ClusterSelection? {
        guard cluster.assetIDs.contains(where: removed.contains) else { return self }
        let survivors = cluster.assetIDs.filter { !removed.contains($0) }
        guard survivors.count >= 2 else { return nil }

        let survivingRanking = ranking.filter { !removed.contains($0.assetID) }
        let keeperSurvived = keeperID.map { !removed.contains($0) } ?? false
        let keeper = keeperSurvived ? keeperID : survivingRanking.first?.assetID

        var deletion = suggestedForDeletion.subtracting(removed)
        if let keeper {
            deletion.remove(keeper)
        }
        if keeper == nil || deletion.count >= survivors.count {
            // Without a keeper nothing is pre-selected, and a suggestion never selects every member.
            deletion = []
        }

        return ClusterSelection(
            cluster: SimilarityCluster(
                id: removed.contains(cluster.id) ? survivors[0] : cluster.id,
                assetIDs: survivors,
                suggestedKeeperID: keeper,
                averageDistance: cluster.averageDistance,
                isExactDuplicate: cluster.isExactDuplicate
            ),
            ranking: survivingRanking,
            suggestedForDeletion: deletion,
            needsReview: needsReview || (keeperID != nil && !keeperSurvived)
        )
    }
}
