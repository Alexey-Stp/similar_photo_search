import Domain
import Foundation

/// `QualityScorer` that returns preset outcomes and records the photos it was asked about.
///
/// Unknown IDs are `.skipped(.notFound)`.
public final class MockQualityScorer: QualityScorer, @unchecked Sendable {
    /// The version returned as `scoringVersion`.
    public let scoringVersion: Int
    private let outcomes: [String: QualityOutcome]
    private let lock = NSLock()
    private var measuredIDs: [String] = []

    /// Creates the mock with outcomes by asset ID.
    public init(outcomes: [String: QualityOutcome] = [:], scoringVersion: Int = 1) {
        self.outcomes = outcomes
        self.scoringVersion = scoringVersion
    }

    /// Creates the mock with measurements by asset ID (all `.measured`).
    public convenience init(measurements: [String: QualityMeasurement], scoringVersion: Int = 1) {
        self.init(outcomes: measurements.mapValues { .measured($0) }, scoringVersion: scoringVersion)
    }

    /// The asset IDs passed to `measure(_:)`, in call order.
    public var calls: [String] {
        lock.withLock { measuredIDs }
    }

    /// Returns the preset outcome; throws `CancellationError` if the task is cancelled.
    public func measure(_ asset: PhotoAsset) async throws -> QualityOutcome {
        try Task.checkCancellation()
        lock.withLock { measuredIDs.append(asset.id) }
        return outcomes[asset.id] ?? .skipped(.notFound)
    }
}
