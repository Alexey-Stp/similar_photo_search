import Domain
import Foundation
import Observation

/// The live keep / delete choice for one cluster.
///
/// One object per cluster, so a cell that reads `isSelected(_:)` re-renders only when *its* cluster changes, not on
/// every toggle anywhere in the list. Mutated only through `SelectionStore`, which enforces the invariants.
@Observable
@MainActor
public final class ClusterSelectionState: Identifiable {
    /// The cluster's ID.
    public let id: String
    /// The Smart Selection suggestion the choice started from.
    public let suggestion: ClusterSelection
    /// The members selected for deletion.
    public internal(set) var selectedIDs: Set<String>
    /// Whether the user confirmed deleting every member of this cluster. Cleared as soon as one member is kept again.
    public internal(set) var isDeleteAllConfirmed: Bool
    /// The photo the user marked as best ("Mark as Best", "Keep This One"), or `nil` to follow the suggestion.
    public internal(set) var chosenKeeperID: String?

    /// The members, in library order.
    public var memberIDs: [String] { suggestion.cluster.assetIDs }
    /// The photo marked **Keep (Best)**: the user's choice, else the suggestion's keeper, if any.
    public var keeperID: String? { chosenKeeperID ?? suggestion.keeperID }
    /// Whether the cluster is flagged "Review recommended".
    public var needsReview: Bool { suggestion.needsReview }
    /// Whether the user's choice differs from the suggestion.
    public var isOverridden: Bool {
        selectedIDs != suggestion.suggestedForDeletion || isDeleteAllConfirmed || chosenKeeperID != nil
    }

    /// Creates the choice of one cluster; only `SelectionStore` does.
    init(
        suggestion: ClusterSelection,
        selectedIDs: Set<String>,
        isDeleteAllConfirmed: Bool,
        chosenKeeperID: String? = nil
    ) {
        id = suggestion.id
        self.suggestion = suggestion
        self.selectedIDs = selectedIDs
        self.isDeleteAllConfirmed = isDeleteAllConfirmed
        self.chosenKeeperID = chosenKeeperID
    }

    /// Whether the member is selected for deletion.
    public func isSelected(_ assetID: String) -> Bool {
        selectedIDs.contains(assetID)
    }

    /// Whether the photo is a member that will be kept.
    public func isKept(_ assetID: String) -> Bool {
        !selectedIDs.contains(assetID) && memberIDs.contains(assetID)
    }
}
