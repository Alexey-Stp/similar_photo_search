import Foundation

extension ScanViewModel {
    /// Clears the groups shown and the user's choices, for "Start Over". The next scan publishes the groups again.
    /// Deletes nothing.
    public func clearResults() {
        selection.reset()
        rowOrder = ClusterRowOrder()
        clusterRevision += 1
    }
}
