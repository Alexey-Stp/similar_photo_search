import Domain
import Foundation

/// `ClusteringEngine` that returns preset clusters and records its input.
public actor MockClusteringEngine: ClusteringEngine {
    /// Clusters returned by every call.
    public let result: [SimilarityCluster]
    /// Inputs received so far.
    public private(set) var receivedBatches: [[FeaturePrint]] = []

    /// Creates the mock.
    public init(result: [SimilarityCluster] = []) {
        self.result = result
    }

    public func clusters(for featurePrints: [FeaturePrint]) -> [SimilarityCluster] {
        receivedBatches.append(featurePrints)
        return result
    }
}
