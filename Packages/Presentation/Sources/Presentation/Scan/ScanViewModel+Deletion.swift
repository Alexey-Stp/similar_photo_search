import Foundation

extension ScanViewModel {
    /// How long after this app's own deletion a library change is attributed to it: the change observer's debounce
    /// (1 s) plus slack for PhotoKit to deliver the change.
    public static let ownChangeQuietPeriod: TimeInterval = 5

    /// The deletion flow is about to ask the system to delete photos. Until `deletionFinished(deleted:)` (and the
    /// quiet period after it), library changes are this app's own deletion and start no rescan.
    public func deletionStarted() {
        deletionsInProgress += 1
    }

    /// The deletion flow got its result: the groups already shown lose the deleted photos (a group left with one
    /// photo disappears; the others keep their row), and the running scan never analyses them. Nothing is rescanned.
    /// - Parameter deleted: Only the photos actually deleted, never the requested ones.
    public func deletionFinished(deleted: Set<String>) async {
        deletionsInProgress = max(0, deletionsInProgress - 1)
        guard !deleted.isEmpty else { return }
        ownChangesQuietUntil = now().addingTimeInterval(Self.ownChangeQuietPeriod)
        // Recorded before the first suspension, so groups the scan already published can't bring them back.
        deletedAssetIDs.formUnion(deleted)
        let update = selection.removeDeleted(deleted)
        rowOrder.rename(update.renamed)
        rowOrder.remove(update.removed)
        if !update.isEmpty {
            clusterRevision += 1
        }
        await coordinator.excludeDeleted(deleted)
    }

    /// Whether a library change now is most likely this app's own deletion (one is running, or finished less than
    /// `ownChangeQuietPeriod` ago). A change from elsewhere in that window is caught by the next change or launch.
    public var isOwnDeletionInProgress: Bool {
        if deletionsInProgress > 0 { return true }
        guard let until = ownChangesQuietUntil else { return false }
        return now() < until
    }
}
