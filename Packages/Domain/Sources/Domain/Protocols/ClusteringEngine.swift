import Foundation

/// Groups the feature prints of one shooting session into clusters of similar photos.
public protocol ClusteringEngine: Sendable {
    /// Clusters the given prints. Prints of different revisions are never compared.
    func clusters(for featurePrints: [FeaturePrint]) async -> [SimilarityCluster]
}
