import Foundation

/// The Smart Selection suggestion for one cluster: which photo to keep as the best, which photos to pre-select for
/// deletion, and whether the user should look before deleting.
///
/// Built by `SmartSelectionUseCase`. It is only a suggestion: the user's own choice lives in `SelectionStore`
/// (Presentation) and wins over it.
public struct ClusterSelection: Sendable, Hashable, Identifiable {
    /// The cluster, with `suggestedKeeperID` set to the photo marked **Keep (Best)**, or `nil` if no member could
    /// be ranked.
    public let cluster: SimilarityCluster
    /// The members that were ranked, best first. Members whose measurement was skipped or failed are missing.
    public let ranking: [RankedMember]
    /// The members pre-selected for deletion. Never contains the keeper, a favorite, a near-tie of the keeper or a
    /// member without a ranking; never contains every member.
    public let suggestedForDeletion: Set<String>
    /// Whether the cluster is flagged "Review recommended": a member scores within the near-tie tolerance of the
    /// keeper, or some members could not be ranked.
    public let needsReview: Bool

    /// The cluster's ID.
    public var id: String { cluster.id }

    /// The photo marked **Keep (Best)**, if any.
    public var keeperID: String? { cluster.suggestedKeeperID }

    /// The members the suggestion keeps, in library order.
    public var keptIDs: [String] {
        cluster.assetIDs.filter { !suggestedForDeletion.contains($0) }
    }

    /// Creates a suggestion.
    public init(
        cluster: SimilarityCluster,
        ranking: [RankedMember],
        suggestedForDeletion: Set<String>,
        needsReview: Bool
    ) {
        self.cluster = cluster
        self.ranking = ranking
        self.suggestedForDeletion = suggestedForDeletion
        self.needsReview = needsReview
    }
}
