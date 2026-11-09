import Domain
import Foundation

/// `FeaturePrintService` that returns preset outcomes; unknown IDs behave like skipped iCloud-only photos.
public actor MockFeaturePrintService: FeaturePrintService {
    /// The revision reported to callers.
    public nonisolated let revision: Int
    /// Outcomes returned by asset ID.
    public let outcomes: [String: FeaturePrintOutcome]
    /// Asset IDs requested so far, in order.
    public private(set) var requestedAssetIDs: [String] = []

    /// Creates the mock with preset outcomes.
    public init(revision: Int = 2, outcomes: [String: FeaturePrintOutcome] = [:]) {
        self.revision = revision
        self.outcomes = outcomes
    }

    /// Creates the mock with prints that are all computed successfully.
    public init(revision: Int = 2, featurePrints: [String: FeaturePrint]) {
        self.init(revision: revision, outcomes: featurePrints.mapValues { .computed($0) })
    }

    public func featurePrint(for asset: PhotoAsset) throws -> FeaturePrintOutcome {
        try Task.checkCancellation()
        requestedAssetIDs.append(asset.id)
        return outcomes[asset.id] ?? .skipped(.iCloudOnly)
    }
}
