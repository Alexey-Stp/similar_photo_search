import Foundation

/// Scores photo quality so the best photo of a cluster can be suggested as the keeper.
public protocol QualityScorer: Sendable {
    /// Returns a quality score for the photo; higher is better.
    func score(assetID: String) async throws -> Double
}
