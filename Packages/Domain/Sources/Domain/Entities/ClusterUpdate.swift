import Foundation

/// A change to the scan's groups, published as soon as a session is done, independent of progress.
///
/// Sessions are published newest first, so a consumer that appends `.added` groups keeps them in date order.
public enum ClusterUpdate: Sendable, Hashable {
    /// New groups of one session, with the Smart Selection suggestion of each. A group whose ID was published
    /// before (in an earlier scan) replaces it.
    case added([ClusterSelection])
    /// Groups that no longer exist, by `SimilarityCluster.id` (the photos changed or were deleted since an earlier
    /// scan). An ID published in the same scan is never removed.
    case removed([String])
    /// The scan ended (done, cancelled or failed; the progress stream says which). Always the last update.
    case finished
}

/// The two streams of a running scan.
public struct ScanStreams: Sendable {
    /// Progress snapshots, at most 10 per second. A slow consumer gets the newest one, never a backlog.
    public let progress: AsyncStream<ScanProgress>
    /// Group changes. Never drops an update; ends after `.finished`.
    public let clusters: AsyncStream<ClusterUpdate>

    /// Creates the pair.
    public init(progress: AsyncStream<ScanProgress>, clusters: AsyncStream<ClusterUpdate>) {
        self.progress = progress
        self.clusters = clusters
    }
}
