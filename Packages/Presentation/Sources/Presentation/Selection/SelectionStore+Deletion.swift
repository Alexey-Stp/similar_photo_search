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
    /// - A cluster left with fewer than two members is removed.
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
            guard let next = state.suggestion.removingMembers(deleted) else {
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

    /// Puts `next` in place of `state` (same row), carrying the user's choice over to the survivors.
    private func replace(_ state: ClusterSelectionState, with next: ClusterSelection) {
        let survivors = Set(next.cluster.assetIDs)
        var selected = state.selectedIDs.intersection(survivors)
        let confirmed = state.isDeleteAllConfirmed && selected == survivors
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
