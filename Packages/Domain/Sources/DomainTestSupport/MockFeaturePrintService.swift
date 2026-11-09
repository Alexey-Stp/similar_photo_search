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
    /// - Parameter revision: The revision to report. By default, the revision of the preset computed prints (2 if
    ///   there are none), so the mock never reports a revision its prints don't have.
    public init(revision: Int? = nil, outcomes: [String: FeaturePrintOutcome] = [:]) {
        let printRevision = outcomes.values.lazy.compactMap(\.featurePrint).first?.revision
        self.revision = revision ?? printRevision ?? 2
        self.outcomes = outcomes
    }

    /// Creates the mock with prints that are all computed successfully.
    /// - Parameter revision: The revision to report; by default the prints' revision (2 if there are none).
    public init(revision: Int? = nil, featurePrints: [String: FeaturePrint]) {
        self.init(revision: revision, outcomes: featurePrints.mapValues { .computed($0) })
    }

    /// Returns the preset outcome for `asset`, or `.skipped(.iCloudOnly)` for an unknown ID, and records the request.
    public func featurePrint(for asset: PhotoAsset) throws -> FeaturePrintOutcome {
        try Task.checkCancellation()
        requestedAssetIDs.append(asset.id)
        return outcomes[asset.id] ?? .skipped(.iCloudOnly)
    }
}
