import Domain
import Foundation

/// In-memory `FeaturePrintCache` that applies the real validity rule (`AnalysisRecord.isValid(for:revision:)`).
public actor MockFeaturePrintCache: FeaturePrintCache {
    /// Stored records by asset ID.
    public private(set) var entries: [String: AnalysisRecord]
    /// Every `upsert(_:)` call, in order.
    public private(set) var upsertCalls: [[AnalysisRecord]] = []
    /// Every ID passed to `purge(assetIDs:)`, in order.
    public private(set) var purgedIDs: [String] = []
    /// When set, `upsert(_:)` and `purge(assetIDs:)` throw it and change nothing.
    public private(set) var writeError: (any Error)?

    /// Creates the mock with some records already stored.
    public init(entries: [AnalysisRecord] = []) {
        self.entries = Dictionary(entries.map { ($0.assetID, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Creates the mock with the records of some computed prints.
    public init(featurePrints: [FeaturePrint], analyzedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.init(entries: featurePrints.map { AnalysisRecord(featurePrint: $0, analyzedAt: analyzedAt) })
    }

    /// Returns the stored records that are valid for `assets` under `revision`.
    public func validEntries(for assets: [PhotoAsset], revision: Int) -> [String: AnalysisRecord] {
        var result: [String: AnalysisRecord] = [:]
        for asset in assets {
            if let entry = entries[asset.id], entry.isValid(for: asset, revision: revision) {
                result[asset.id] = entry
            }
        }
        return result
    }

    /// Records the call and stores `records`, or throws `writeError`.
    public func upsert(_ records: [AnalysisRecord]) throws {
        if let writeError { throw writeError }
        upsertCalls.append(records)
        for record in records {
            entries[record.assetID] = record
        }
    }

    /// Records the IDs and removes their records, or throws `writeError`.
    public func purge(assetIDs: [String]) throws {
        if let writeError { throw writeError }
        purgedIDs.append(contentsOf: assetIDs)
        for id in assetIDs {
            entries[id] = nil
        }
    }

    /// The IDs of all stored records.
    public func cachedAssetIDs() -> Set<String> {
        Set(entries.keys)
    }

    /// Sets or clears the error that writes throw.
    public func setWriteError(_ error: (any Error)?) {
        writeError = error
    }
}
