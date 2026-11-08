import Domain
import Foundation

/// Vision-based quality scorer (face capture quality, aesthetics, sharpness). Placeholder until its ticket.
public actor VisionQualityScorer: QualityScorer {
    /// Creates the scorer.
    public init() {}

    public func score(assetID: String) async throws -> Double {
        fatalError("Not implemented")
    }
}
