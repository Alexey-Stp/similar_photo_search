import Domain
import Foundation

/// `QualityScorer` that returns preset scores (default `0`).
public actor MockQualityScorer: QualityScorer {
    /// Scores by asset ID.
    public let scores: [String: Double]

    /// Creates the mock.
    public init(scores: [String: Double] = [:]) {
        self.scores = scores
    }

    public func score(assetID: String) -> Double {
        scores[assetID] ?? 0
    }
}
