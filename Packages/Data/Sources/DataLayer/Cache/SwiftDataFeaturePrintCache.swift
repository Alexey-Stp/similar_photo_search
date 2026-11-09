import Domain
import Foundation
import SwiftData

/// SwiftData-backed analysis cache (`FeaturePrintCache`).
///
/// The store is opened lazily on first use, off the main thread, so building the cache in `AppContainer` costs
/// nothing at launch. All reads and writes go through one `@ModelActor` (`AnalysisStore`) with its own background
/// context. If the store can't be opened it is deleted and rebuilt (see `AnalysisContainerFactory`); if even an
/// in-memory store fails, every read is a miss and writes throw `FeaturePrintCacheError.unavailable`.
public actor SwiftDataFeaturePrintCache: FeaturePrintCache {
    /// Where the store lives.
    public enum Location: Sendable, Hashable {
        /// Application Support/Analysis/Analysis.store, excluded from backup. The app's store.
        case applicationSupport
        /// `Analysis.store` inside the given directory, prepared like Application Support/Analysis. For tests.
        case directory(URL)
        /// In memory only; nothing survives the cache. For tests and previews.
        case inMemory
    }

    /// Records written per `save()`.
    public static let writeBatchSize = AnalysisStore.writeBatchSize

    private let location: Location
    private var store: AnalysisStore?
    private var didOpen = false

    /// Creates the app's cache in Application Support.
    public init() {
        self.init(location: .applicationSupport)
    }

    /// Creates a cache at `location`.
    public init(location: Location) {
        self.location = location
    }

    /// Returns the valid records for `assets` under `revision`; an unavailable store gives no hits.
    public func validEntries(for assets: [PhotoAsset], revision: Int) async -> [String: AnalysisRecord] {
        guard !assets.isEmpty, let store = openStore() else { return [:] }
        return await store.validEntries(for: assets, revision: revision)
    }

    /// Stores `records`, replacing earlier records of the same assets; saves every `writeBatchSize`.
    public func upsert(_ records: [AnalysisRecord]) async throws {
        guard !records.isEmpty else { return }
        guard let store = openStore() else { throw FeaturePrintCacheError.unavailable }
        try await store.upsert(records)
    }

    /// Removes the records of `assetIDs`; unknown IDs are ignored.
    public func purge(assetIDs: [String]) async throws {
        guard !assetIDs.isEmpty else { return }
        guard let store = openStore() else { throw FeaturePrintCacheError.unavailable }
        try await store.purge(assetIDs: assetIDs)
    }

    /// The number of stored records of any revision, or `nil` if the store is unavailable.
    public func recordCount() async -> Int? {
        guard let store = openStore() else { return nil }
        return try? await store.count()
    }

    /// Whether the store has been opened (or an attempt was made).
    var isOpened: Bool { didOpen }

    /// The opened store, opening it on the first call.
    func openStore() -> AnalysisStore? {
        if !didOpen {
            didOpen = true
            if let container = AnalysisContainerFactory.makeContainer(location: location) {
                store = AnalysisStore(modelContainer: container)
            }
        }
        return store
    }
}

/// Errors of `SwiftDataFeaturePrintCache` writes.
public enum FeaturePrintCacheError: Error, Sendable, Hashable {
    /// No store could be opened, not even in memory.
    case unavailable
}
