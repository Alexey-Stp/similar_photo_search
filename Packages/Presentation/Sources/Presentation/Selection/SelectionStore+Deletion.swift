import Domain
import Foundation

/// What `SelectionStore.removeDeleted(_:)` changed.
public struct DeletionUpdate: Sendable, Equatable {
    /// Clusters whose ID changed because the photo that named them was deleted: old ID → new ID.
    public var renamed: [String: String] = [:]
    /// Clusters that lost members and still exist, by their current ID.
    public var updated: [String] = []
    /// Clusters removed because fewer than two members were left.
    public var removed: [String] = []

    /// Whether nothing changed.
    public var isEmpty: Bool { updated.isEmpty && removed.isEmpty }
}

extension SelectionStore {
    /// Updates the clusters after their photos were deleted (SPS-25), locally and without a rescan.
    ///
    /// - A cluster left with fewer than two members is removed, except a single survivor that is still selected
    ///   (the user deleted the whole group and that photo failed): it stays as a one-photo group, selected.
    /// - Any other affected cluster is recomputed (`ClusterSelection.removingMembers(_:)`) under the same ID, or under
    ///   its newest survivor's ID when the naming photo was deleted. The user's choice for the survivors is kept:
    ///   what they selected stays selected (for example a photo that could not be deleted), and a chosen Best that
    ///   survived stays the Best. The choice is recorded for the new member set, so a rescan that publishes the same
    ///   members restores it.
    /// - Deleted photos leave the selection, the count and the summary.
    @discardableResult
    public func removeDeleted(_ deleted: Set<String>) -> DeletionUpdate {
        var update = DeletionUpdate()
        guard !deleted.isEmpty else { return update }
        for clusterID in clusterIDs {
            guard let state = states[clusterID], state.memberIDs.contains(where: deleted.contains) else { continue }
            guard let next = state.suggestion.removingMembers(deleted) ?? failedLeftover(of: state, deleted) else {
                update.removed.append(clusterID)
                continue
            }
            replace(state, with: next)
            if next.id != clusterID {
                update.renamed[clusterID] = next.id
            }
            update.updated.append(next.id)
        }
        for id in update.removed {
            overrides[id] = nil
        }
        // `remove` refreshes the totals; without removals they are refreshed here.
        if update.removed.isEmpty {
            refreshTotals()
        } else {
            remove(clusterIDs: update.removed)
        }
        return update
    }

    /// The summary of exactly `assetIDs`, from the sizes estimated so far (the deletion review and its result).
    func summary(of assetIDs: [String]) -> DeletionSummary {
        makeSummary(for: assetIDs)
    }

    /// The ID of the cluster that holds the photo, if any.
    func clusterID(containing assetID: String) -> String? {
        clusterIDByAsset[assetID]
    }

    /// A one-photo group for the only survivor of a group the user wanted to delete entirely, when that photo is still
    /// selected (its deletion failed): it stays visible and selectable for a retry. `nil` for any other leftover.
    private func failedLeftover(of state: ClusterSelectionState, _ deleted: Set<String>) -> ClusterSelection? {
        let survivors = state.memberIDs.filter { !deleted.contains($0) }
        guard survivors.count == 1, let survivor = survivors.first, state.selectedIDs.contains(survivor) else {
            return nil
        }
        return ClusterSelection(
            cluster: SimilarityCluster(
                id: deleted.contains(state.id) ? survivor : state.id,
                assetIDs: [survivor],
                averageDistance: state.suggestion.cluster.averageDistance,
                isExactDuplicate: state.suggestion.cluster.isExactDuplicate
            ),
            ranking: state.suggestion.ranking.filter { $0.assetID == survivor },
            suggestedForDeletion: [],
            needsReview: true
        )
    }

    /// Puts `next` in place of `state` (same row), carrying the user's choice over to the survivors.
    private func replace(_ state: ClusterSelectionState, with next: ClusterSelection) {
        let survivors = Set(next.cluster.assetIDs)
        var selected = state.selectedIDs.intersection(survivors)
        // A failed leftover of one photo stays selected: the user already confirmed deleting the whole group.
        let confirmed = (state.isDeleteAllConfirmed || survivors.count == 1) && selected == survivors
        if selected == survivors, !confirmed, let kept = next.keeperID ?? next.cluster.assetIDs.first {
            // A cluster keeps at least one photo unless the user confirmed otherwise.
            selected.remove(kept)
        }
        let chosen = state.chosenKeeperID.flatMap { survivors.contains($0) && $0 != next.keeperID ? $0 : nil }

        unindex(state)
        states[state.id] = nil
        overrides[state.id] = nil
        let replacement = ClusterSelectionState(
            suggestion: next,
            selectedIDs: selected,
            isDeleteAllConfirmed: confirmed,
            chosenKeeperID: chosen
        )
        states[next.id] = replacement
        if let index = clusterIDs.firstIndex(of: state.id), state.id != next.id {
            clusterIDs[index] = next.id
        }
        for id in next.cluster.assetIDs {
            clusterIDByAsset[id] = next.id
        }
        recordOverride(of: replacement)
    }
}
