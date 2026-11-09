import Foundation

/// Groups the photos of one shooting session into clusters of similar photos.
///
/// Synchronous and pure: parallelism, ordering across sessions and live publishing belong to the scan coordinator.
public protocol ClusteringEngine: Sendable {
    /// Clusters the items of one session.
    ///
    /// Items are partitioned by revision (and vector length) first, so items of different revisions never share a
    /// cluster. The result holds only clusters of two or more photos, newest cluster first, and is the same for the
    /// same input regardless of its order.
    ///
    /// - Throws: `ClusteringError.missingThreshold` if two or more items have a revision without a threshold.
    func clusters(in session: [VectorItem], config: ClusteringConfig) throws(ClusteringError) -> [SimilarityCluster]
}
