import Domain
import Foundation

/// Distance-threshold + Union-Find clustering of one shooting session. Placeholder until the clustering ticket.
public actor UnionFindClusteringEngine: ClusteringEngine {
    /// Creates the engine.
    public init() {}

    public func clusters(for featurePrints: [FeaturePrint]) async -> [SimilarityCluster] {
        fatalError("Not implemented")
    }
}
