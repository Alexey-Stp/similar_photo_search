#if DEBUG
import Domain

/// `AssetSizeEstimator` for SwiftUI previews: every photo is 3 MB.
struct PreviewAssetSizeEstimator: AssetSizeEstimator {
    /// Returns 3 MB for every ID.
    func estimatedSizes(of assetIDs: [String]) async -> [String: Int64] {
        Dictionary(uniqueKeysWithValues: assetIDs.map { ($0, Int64(3_000_000)) })
    }
}

extension SelectionStore {
    /// A store with two suggested clusters: one with two photos pre-selected, one flagged "Review recommended".
    static func preview() -> SelectionStore {
        let store = SelectionStore(sizes: PreviewAssetSizeEstimator())
        store.upsert([
            ClusterSelection(
                cluster: SimilarityCluster(assetIDs: ["A1", "A2", "A3"], suggestedKeeperID: "A1"),
                ranking: [],
                suggestedForDeletion: ["A2", "A3"],
                needsReview: false
            ),
            ClusterSelection(
                cluster: SimilarityCluster(assetIDs: ["B1", "B2"], suggestedKeeperID: "B2"),
                ranking: [],
                suggestedForDeletion: [],
                needsReview: true
            )
        ])
        return store
    }
}
#endif
