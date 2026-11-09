import Domain
import DomainTestSupport
import Foundation
import Testing

/// Pins down the cache contract that the real SwiftData cache must also follow.
struct MockFeaturePrintCacheTests {
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_100)

    private func asset(_ id: String = "A", modified: Date? = nil) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: modificationDate,
            modificationDate: modified ?? modificationDate,
            pixelWidth: 100,
            pixelHeight: 100,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    private func record(_ id: String = "A", revision: Int = 2) -> AnalysisRecord {
        AnalysisRecord(
            featurePrint: FeaturePrint(
                assetID: id,
                revision: revision,
                vector: [0.1, 0.2],
                assetModificationDate: modificationDate
            ),
            analyzedAt: analyzedAt
        )
    }

    @Test func returnsEntryWhenIDRevisionAndDateMatch() async {
        let cache = MockFeaturePrintCache(entries: [record()])
        let hits = await cache.validEntries(for: [asset()], revision: 2)
        #expect(hits == ["A": record()])
    }

    @Test func missesWhenRevisionDiffers() async {
        let cache = MockFeaturePrintCache(entries: [record(revision: 1)])
        let hits = await cache.validEntries(for: [asset()], revision: 2)
        #expect(hits.isEmpty)
    }

    @Test func missesWhenAssetWasModified() async {
        let cache = MockFeaturePrintCache(entries: [record()])
        let edited = asset(modified: modificationDate.addingTimeInterval(60))
        let hits = await cache.validEntries(for: [edited], revision: 2)
        #expect(hits.isEmpty)
    }

    @Test func returnsOnlyTheRequestedAssets() async {
        let cache = MockFeaturePrintCache(entries: [record("A"), record("B")])
        let hits = await cache.validEntries(for: [asset("B"), asset("C")], revision: 2)
        #expect(Set(hits.keys) == ["B"])
    }

    @Test func upsertReplacesPreviousEntry() async throws {
        let cache = MockFeaturePrintCache(entries: [record(revision: 1)])
        try await cache.upsert([record(revision: 2)])
        let hits = await cache.validEntries(for: [asset()], revision: 2)
        #expect(hits["A"]?.revision == 2)
    }

    @Test func purgeRemovesEntries() async throws {
        let cache = MockFeaturePrintCache(entries: [record("A"), record("B")])
        try await cache.purge(assetIDs: ["A", "unknown"])
        let hits = await cache.validEntries(for: [asset("A"), asset("B")], revision: 2)
        #expect(Set(hits.keys) == ["B"])
        #expect(await cache.purgedIDs == ["A", "unknown"])
    }

    @Test func writeErrorLeavesEntriesUnchanged() async {
        struct Failure: Error {}
        let cache = MockFeaturePrintCache(entries: [record("A")])
        await cache.setWriteError(Failure())
        await #expect(throws: Failure.self) { try await cache.upsert([record("B")]) }
        await #expect(throws: Failure.self) { try await cache.purge(assetIDs: ["A"]) }
        #expect(await Set(cache.entries.keys) == ["A"])
    }
}
