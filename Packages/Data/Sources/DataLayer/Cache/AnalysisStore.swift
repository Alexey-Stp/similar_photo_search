import Domain
import Foundation
import os
import SwiftData

/// The only writer of the analysis cache: every read and write runs on this actor's own background `ModelContext`,
/// never the main context.
///
/// Only `AnalysisRecord` values cross the actor boundary, never `CachedAnalysis` instances. Concurrent upserts of the
/// same asset are serialized by the actor, so the unique `assetID` never sees two inserts at once.
@ModelActor
actor AnalysisStore {
    /// Records inserted or updated per `save()`.
    static let writeBatchSize = 200
    /// Asset IDs per fetch, which keeps the SQL `IN` list well under SQLite's variable limit.
    static let fetchBatchSize = 500

    private static let logger = Logger(subsystem: "com.similarphotos", category: "analysisCache")

    /// How many times `save()` was called; lets tests check the batching.
    private(set) var saveCount = 0

    /// The valid records of `assets` under `revision`, keyed by asset ID.
    ///
    /// Reads in chunks of `fetchBatchSize` IDs; rows whose vector bytes or status can't be decoded count as misses.
    func validEntries(for assets: [PhotoAsset], revision: Int) -> [String: AnalysisRecord] {
        var assetsByID: [String: PhotoAsset] = [:]
        assetsByID.reserveCapacity(assets.count)
        for asset in assets {
            assetsByID[asset.id] = asset
        }
        let ids = Array(assetsByID.keys)
        var result: [String: AnalysisRecord] = [:]
        result.reserveCapacity(ids.count)
        do {
            for start in stride(from: 0, to: ids.count, by: Self.fetchBatchSize) {
                let chunk = Array(ids[start..<min(start + Self.fetchBatchSize, ids.count)])
                try autoreleasepool {
                    for model in try fetch(ids: chunk, revision: revision) {
                        guard let asset = assetsByID[model.assetID],
                              let record = model.record,
                              record.isValid(for: asset, revision: revision) else {
                            continue
                        }
                        result[record.assetID] = record
                    }
                }
            }
        } catch {
            Self.logger.error("Analysis cache read failed: \(String(describing: error), privacy: .private)")
        }
        return result
    }

    /// Inserts or replaces records, saving every `writeBatchSize` records. The last record of an asset wins.
    func upsert(_ records: [AnalysisRecord]) throws {
        var latest: [String: AnalysisRecord] = [:]
        var order: [String] = []
        for record in records {
            let isFirst = latest[record.assetID] == nil
            latest[record.assetID] = record
            if isFirst { order.append(record.assetID) }
        }
        for start in stride(from: 0, to: order.count, by: Self.writeBatchSize) {
            let chunk = Array(order[start..<min(start + Self.writeBatchSize, order.count)])
            try autoreleasepool {
                let existing = try fetch(ids: chunk, revision: nil)
                var modelsByID: [String: CachedAnalysis] = [:]
                for model in existing {
                    modelsByID[model.assetID] = model
                }
                for id in chunk {
                    guard let record = latest[id] else { continue }
                    if let model = modelsByID[id] {
                        model.update(from: record)
                    } else {
                        modelContext.insert(CachedAnalysis(record))
                    }
                }
                try save()
            }
        }
    }

    /// Deletes the records of `assetIDs`, saving once per `fetchBatchSize` IDs.
    func purge(assetIDs: [String]) throws {
        let ids = Array(Set(assetIDs))
        for start in stride(from: 0, to: ids.count, by: Self.fetchBatchSize) {
            let chunk = Array(ids[start..<min(start + Self.fetchBatchSize, ids.count)])
            try autoreleasepool {
                let predicate = #Predicate<CachedAnalysis> { chunk.contains($0.assetID) }
                var descriptor = FetchDescriptor<CachedAnalysis>(predicate: predicate)
                descriptor.propertiesToFetch = [\.assetID]
                let models = try modelContext.fetch(descriptor)
                guard !models.isEmpty else { return }
                for model in models {
                    modelContext.delete(model)
                }
                try save()
            }
        }
    }

    /// The number of stored records, of any revision.
    func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<CachedAnalysis>())
    }

    // MARK: - Private

    /// The rows for `ids`, restricted to `revision` if given. Flat rows only: the model has no relationships.
    private func fetch(ids: [String], revision: Int?) throws -> [CachedAnalysis] {
        let predicate: Predicate<CachedAnalysis>
        if let revision {
            predicate = #Predicate<CachedAnalysis> { ids.contains($0.assetID) && $0.revision == revision }
        } else {
            predicate = #Predicate<CachedAnalysis> { ids.contains($0.assetID) }
        }
        var descriptor = FetchDescriptor<CachedAnalysis>(predicate: predicate)
        descriptor.propertiesToFetch = [
            \.assetID, \.vectorData, \.revision, \.modificationDate, \.qualityScore, \.status, \.analyzedAt
        ]
        return try modelContext.fetch(descriptor)
    }

    private func save() throws {
        try modelContext.save()
        saveCount += 1
    }
}
