import Foundation

/// Suggests, for each cluster, which photo to keep and which to pre-select for deletion. Pure and deterministic.
///
/// Rules, from the most to the least important (deleting a photo the user wanted is the worst outcome, so every
/// doubt keeps the photo):
/// 1. A member without quality signals (its measurement was skipped or failed) is never pre-selected, and the
///    cluster is flagged `needsReview`.
/// 2. A favorite is never pre-selected. Several favorites are all kept.
/// 3. The keeper (**Keep (Best)**) is the top-ranked member (`QualityRanker`). In an exact-duplicate cluster it is the
///    member with the most pixels, then the edited one, then the better ranked one.
/// 4. Outside exact duplicates, every member whose weighted score is within `nearTieTolerance` of the keeper's is
///    kept too, and the cluster is flagged `needsReview`. Exact duplicates skip this rule: they look the same, so
///    resolution and edits decide.
/// 5. Everything else is pre-selected. At least one member is always kept.
public struct SmartSelectionUseCase: Sendable {
    /// The default near-tie tolerance on the weighted score (0…1).
    public static let defaultNearTieTolerance = 0.02

    /// Two scores at most this far apart count as a near-tie.
    public let nearTieTolerance: Double
    /// The weights passed to `QualityRanker`.
    public let weights: QualityWeights
    private let ranker = QualityRanker()

    /// Creates the use case.
    public init(nearTieTolerance: Double = Self.defaultNearTieTolerance, weights: QualityWeights = .standard) {
        self.nearTieTolerance = max(0, nearTieTolerance)
        self.weights = weights
    }

    /// Suggests a selection for every cluster, in the given order.
    /// - Parameter signals: Quality signals by asset ID; may hold photos of other clusters too.
    public func suggest(for clusters: [SimilarityCluster], signals: [String: QualitySignals]) -> [ClusterSelection] {
        clusters.map { suggest(for: $0, signals: signals) }
    }

    /// Suggests a selection for one cluster.
    /// - Parameter signals: Quality signals by asset ID; only the cluster's members are used.
    public func suggest(for cluster: SimilarityCluster, signals: [String: QualitySignals]) -> ClusterSelection {
        var memberIDs: [String] = []
        var seen = Set<String>()
        for id in cluster.assetIDs where seen.insert(id).inserted {
            memberIDs.append(id)
        }
        let memberSignals = signals.filter { seen.contains($0.key) }
        let ranking = ranker.rank(memberSignals, weights: weights)

        let isExact = cluster.isExactDuplicate
        guard let keeper = keeper(in: ranking, signals: memberSignals, isExactDuplicate: isExact) else {
            return ClusterSelection(
                cluster: cluster.withKeeper(nil),
                ranking: ranking,
                suggestedForDeletion: [],
                needsReview: memberIDs.count > 1
            )
        }

        var kept: Set<String> = [keeper.assetID]
        let rankedIDs = Set(ranking.map(\.assetID))
        let unranked = memberIDs.filter { !rankedIDs.contains($0) }
        kept.formUnion(unranked)
        kept.formUnion(ranking.filter(\.isProtected).map(\.assetID))

        var hasNearTie = false
        if !cluster.isExactDuplicate {
            // A tiny slack absorbs floating-point noise, so a difference of exactly the tolerance counts as a tie.
            let limit = nearTieTolerance + 1e-9
            for member in ranking where member.assetID != keeper.assetID && abs(member.score - keeper.score) <= limit {
                kept.insert(member.assetID)
                hasNearTie = true
            }
        }

        return ClusterSelection(
            cluster: cluster.withKeeper(keeper.assetID),
            ranking: ranking,
            suggestedForDeletion: Set(memberIDs.filter { !kept.contains($0) }),
            needsReview: hasNearTie || !unranked.isEmpty
        )
    }

    /// The member to mark **Keep (Best)**, or `nil` if nothing was ranked.
    private func keeper(
        in ranking: [RankedMember],
        signals: [String: QualitySignals],
        isExactDuplicate: Bool
    ) -> RankedMember? {
        guard isExactDuplicate else { return ranking.first }
        // `ranking` is best first, so on equal pixels and edits the better ranked member stays in front.
        return ranking.enumerated().min { lhs, rhs in
            let left = signals[lhs.element.assetID]
            let right = signals[rhs.element.assetID]
            let leftPixels = left?.pixelCount ?? 0
            let rightPixels = right?.pixelCount ?? 0
            if leftPixels != rightPixels { return leftPixels > rightPixels }
            let leftEdited = left?.isEdited ?? false
            let rightEdited = right?.isEdited ?? false
            if leftEdited != rightEdited { return leftEdited }
            return lhs.offset < rhs.offset
        }?.element
    }
}

extension SimilarityCluster {
    /// A copy with the same `id` and members and the given suggested keeper.
    public func withKeeper(_ keeperID: String?) -> SimilarityCluster {
        SimilarityCluster(
            id: id,
            assetIDs: assetIDs,
            suggestedKeeperID: keeperID,
            averageDistance: averageDistance,
            isExactDuplicate: isExactDuplicate
        )
    }
}
