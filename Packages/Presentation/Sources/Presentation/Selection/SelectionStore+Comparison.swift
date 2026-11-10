import Foundation

extension SelectionStore {
    /// "Mark as Best": makes the photo the cluster's **Best** and keeps it. Other photos keep their choice.
    ///
    /// Recorded as an override like a toggle; marking the suggested keeper again goes back to the suggestion.
    /// - Returns: `false` if the cluster is unknown or the photo is not a member (nothing changed).
    @discardableResult
    public func markAsBest(_ assetID: String, in clusterID: String) -> Bool {
        guard let state = states[clusterID], state.memberIDs.contains(assetID) else { return false }
        choose(assetID, asKeeperOf: state)
        if state.selectedIDs.contains(assetID) {
            state.selectedIDs.remove(assetID)
            state.isDeleteAllConfirmed = false
        }
        recordOverride(of: state)
        refreshTotals()
        return true
    }

    /// "Keep This One": keeps the photo, marks it **Best**, and selects every other member for deletion.
    ///
    /// The cluster still keeps one photo, so no confirmation is needed. This is the user's explicit choice, so it
    /// also selects favorites; `excluded` photos (deleted outside the app) are left unselected.
    /// - Returns: `false` if the cluster is unknown or the photo is not a member (nothing changed).
    @discardableResult
    public func keepOnly(_ assetID: String, in clusterID: String, excluding excluded: Set<String> = []) -> Bool {
        guard let state = states[clusterID], state.memberIDs.contains(assetID) else { return false }
        choose(assetID, asKeeperOf: state)
        let selected = Set(state.memberIDs).subtracting([assetID]).subtracting(excluded)
        if state.selectedIDs != selected {
            state.selectedIDs = selected
        }
        if state.isDeleteAllConfirmed {
            state.isDeleteAllConfirmed = false
        }
        recordOverride(of: state)
        refreshTotals()
        return true
    }

    /// Stores the user's keeper, or clears it when it is the suggested one.
    private func choose(_ assetID: String, asKeeperOf state: ClusterSelectionState) {
        let chosen = assetID == state.suggestion.keeperID ? nil : assetID
        if state.chosenKeeperID != chosen {
            state.chosenKeeperID = chosen
        }
    }
}
