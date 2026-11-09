import Foundation

/// Use case: the first step of every scan. Reads the library changes, completes the full-diff fallback, and evicts
/// the analysis records of deleted photos.
///
/// Call `prepare()` before enumerating the library (it reads the start token), and
/// `LibraryChangeTracker.commitScanCompleted()` after the scan succeeded.
public struct IncrementalScanPreparer: Sendable {
    private let tracker: any LibraryChangeTracker
    private let cache: any FeaturePrintCache

    /// Creates the use case.
    public init(tracker: any LibraryChangeTracker, cache: any FeaturePrintCache) {
        self.tracker = tracker
        self.cache = cache
    }

    /// The delta for this scan.
    ///
    /// - With a usable history: the tracker's delta.
    /// - Without one: `LibraryDelta.fullDiff` of the current photos against `FeaturePrintCache.cachedAssetIDs()`.
    ///
    /// The records of `deleted` photos are purged. A failed purge is ignored: the leftover rows are never read
    /// (a deleted `localIdentifier` does not come back) and the next full diff removes them.
    /// Edited photos are not purged: their new modification date already makes their records invalid, and a
    /// change that keeps the date (a favorite flag) does not change the pixels.
    ///
    /// Throws `CancellationError` if cancelled, and whatever the tracker throws.
    public func prepare() async throws -> LibraryDelta {
        let delta: LibraryDelta
        switch try await tracker.changesSinceLastScan() {
        case .changes(let changes):
            delta = changes
        case let .historyUnavailable(reason, currentAssetIDs):
            let cachedIDs = await cache.cachedAssetIDs()
            try Task.checkCancellation()
            delta = .fullDiff(currentIDs: currentAssetIDs, cachedIDs: cachedIDs, reason: reason)
        }
        if !delta.deleted.isEmpty {
            try? await cache.purge(assetIDs: delta.deleted.sorted())
        }
        try Task.checkCancellation()
        return delta
    }
}
