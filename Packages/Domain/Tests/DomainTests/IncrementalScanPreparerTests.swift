import Domain
import DomainTestSupport
import Foundation
import Testing

struct IncrementalScanPreparerTests {
    struct TrackerError: Error {}

    private static func record(_ id: String) -> AnalysisRecord {
        AnalysisRecord(
            assetID: id,
            revision: 2,
            assetModificationDate: nil,
            status: .analyzed,
            vector: [1, 0],
            analyzedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func incrementalDeltaIsPassedThroughAndDeletedRecordsAreEvicted() async throws {
        let cache = MockFeaturePrintCache(entries: [Self.record("kept"), Self.record("gone"), Self.record("edited")])
        let tracker = MockLibraryChangeTracker(
            report: .changes(LibraryDelta(inserted: ["new"], updated: ["edited"], deleted: ["gone"]))
        )
        let delta = try await IncrementalScanPreparer(tracker: tracker, cache: cache).prepare()

        #expect(delta == LibraryDelta(inserted: ["new"], updated: ["edited"], deleted: ["gone"]))
        #expect(await cache.purgedIDs == ["gone"])
        // An edited photo is not purged: its new modification date makes the record a miss.
        #expect(await cache.cachedAssetIDs() == ["kept", "edited"])
        #expect(await tracker.commitCallCount == 0, "Committing is the caller's job, after the scan")
    }

    @Test func noChangesTouchesNothing() async throws {
        let cache = MockFeaturePrintCache(entries: [Self.record("a")])
        let delta = try await IncrementalScanPreparer(tracker: MockLibraryChangeTracker(), cache: cache).prepare()
        #expect(delta.isEmpty)
        #expect(await cache.purgedIDs.isEmpty)
    }

    @Test(arguments: FullRescanReason.allCases)
    func unavailableHistoryFallsBackToAFullDiff(reason: FullRescanReason) async throws {
        let cache = MockFeaturePrintCache(entries: [Self.record("kept"), Self.record("gone")])
        let tracker = MockLibraryChangeTracker(report: .historyUnavailable(reason, currentAssetIDs: ["kept", "new"]))
        let delta = try await IncrementalScanPreparer(tracker: tracker, cache: cache).prepare()

        #expect(delta.isFullRescanRequired)
        #expect(delta.fullRescanReason == reason)
        #expect(delta.inserted == ["new"])
        #expect(delta.deleted == ["gone"])
        #expect(await cache.purgedIDs == ["gone"])
    }

    @Test func failedPurgeDoesNotFailTheScan() async throws {
        let cache = MockFeaturePrintCache(entries: [Self.record("gone")])
        await cache.setWriteError(TrackerError())
        let tracker = MockLibraryChangeTracker(report: .changes(LibraryDelta(deleted: ["gone"])))
        let delta = try await IncrementalScanPreparer(tracker: tracker, cache: cache).prepare()
        #expect(delta.deleted == ["gone"])
    }

    @Test func trackerErrorsAreRethrown() async {
        let tracker = MockLibraryChangeTracker()
        await tracker.setError(CancellationError())
        await #expect(throws: CancellationError.self) {
            try await IncrementalScanPreparer(tracker: tracker, cache: MockFeaturePrintCache()).prepare()
        }
    }
}
