import Foundation

extension SelectionStore {
    /// Forgets every cluster and every choice the user made ("Start Over"). Deletes nothing.
    public func reset() {
        states = [:]
        clusterIDByAsset = [:]
        clusterIDs = []
        overrides = [:]
        refreshTotals()
    }
}
