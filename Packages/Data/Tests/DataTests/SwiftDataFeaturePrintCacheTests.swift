@testable import DataLayer
import Domain
import Foundation
import SwiftData
import Testing

/// The SwiftData cache against in-memory and temporary-directory stores.
@Suite(.timeLimit(.minutes(1)))
struct SwiftDataFeaturePrintCacheTests {
    /// Sub-second on purpose: the date must survive the SQLite round trip exactly.
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000.123_456)
    private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_500.5)

    /// A photo whose modification date is `modified`, or `modificationDate` if `nil`.
    private func asset(_ id: String, modified: Date? = nil) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: modificationDate,
            modificationDate: modified ?? modificationDate,
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A complete quality measurement with every optional set, so the round trip checks each column.
    private let measurement = QualityMeasurement(
        version: 1_031,
        sharpness: 0.012_5,
        faceQuality: 0.62,
        aesthetics: -0.3,
        isUtility: false,
        isEdited: true
    )

    /// A Revision 2 sized vector whose values depend on `seed`.
    private func vector(seed: Int, count: Int = 768) -> [Float] {
        (0..<count).map { Float(seed) + Float($0) / 1_000 }
    }

    /// The analyzed record of a print of `id` with `vector(seed:)`.
    private func record(
        _ id: String,
        revision: Int = 2,
        seed: Int = 1,
        quality: QualityMeasurement? = nil
    ) -> AnalysisRecord {
        AnalysisRecord(
            featurePrint: FeaturePrint(
                assetID: id,
                revision: revision,
                vector: vector(seed: seed),
                assetModificationDate: modificationDate
            ),
            quality: quality,
            analyzedAt: analyzedAt
        )
    }

    /// A fresh, empty directory that `body` may use as the store location; removed afterwards.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AnalysisCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    // MARK: - Round trip and validity

    /// Analyzed and failed records come back field for field, including sub-second dates.
    @Test func storedRecordsComeBackUnchanged() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let analyzed = record("A", quality: measurement)
        let failed = AnalysisRecord(
            assetID: "B",
            revision: 2,
            assetModificationDate: nil,
            status: .failed,
            analyzedAt: analyzedAt
        )
        try await cache.upsert([analyzed, failed])

        let hits = await cache.validEntries(
            for: [asset("A"), PhotoAsset(
                id: "B",
                creationDate: modificationDate,
                modificationDate: nil,
                pixelWidth: 1,
                pixelHeight: 1,
                isFavorite: false,
                mediaSubtypes: []
            )],
            revision: 2
        )
        #expect(hits["A"] == analyzed)
        #expect(hits["A"]?.featurePrint?.vector == vector(seed: 1))
        #expect(hits["B"] == failed)
    }

    /// A record of another revision is a miss, but still a hit for its own revision.
    @Test func aDifferentRevisionIsAMiss() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A", revision: 1)])
        #expect(await cache.validEntries(for: [asset("A")], revision: 2).isEmpty)
        #expect(await cache.validEntries(for: [asset("A")], revision: 1).count == 1)
    }

    /// A photo edited after its analysis is a miss.
    @Test func aModifiedPhotoIsAMiss() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A")])
        let edited = asset("A", modified: modificationDate.addingTimeInterval(1))
        #expect(await cache.validEntries(for: [edited], revision: 2).isEmpty)
    }

    /// Photos without a record are left out of the result.
    @Test func unknownAssetsAreMisses() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A")])
        let hits = await cache.validEntries(for: [asset("A"), asset("unknown")], revision: 2)
        #expect(Set(hits.keys) == ["A"])
    }

    /// A measurement without faces or aesthetics keeps those `nil`, and a record without one has none.
    @Test func qualityMeasurementsRoundTripWithTheirNils() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let partial = QualityMeasurement(
            version: 1_030,
            sharpness: 0.5,
            faceQuality: nil,
            aesthetics: nil,
            isUtility: nil,
            isEdited: false
        )
        try await cache.upsert([record("A", quality: partial), record("B")])

        let hits = await cache.validEntries(for: [asset("A"), asset("B")], revision: 2)
        #expect(hits["A"]?.quality == partial)
        #expect(hits["A"]?.quality(scoringVersion: 1_030) == partial)
        #expect(hits["B"]?.quality == nil)
    }

    /// Adding a measurement to a cached record replaces the row; clearing it removes every quality column.
    @Test func upsertAddsAndClearsTheMeasurement() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A")])
        try await cache.upsert([record("A").withQuality(measurement)])
        #expect(await cache.validEntries(for: [asset("A")], revision: 2)["A"]?.quality == measurement)

        try await cache.upsert([record("A")])
        #expect(await cache.validEntries(for: [asset("A")], revision: 2)["A"]?.quality == nil)
    }

    // MARK: - Writes

    /// An upsert replaces the asset's earlier record, and the last duplicate in one call wins.
    @Test func upsertReplacesTheRecordOfTheSameAsset() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A", revision: 1, seed: 1)])
        try await cache.upsert([record("A", revision: 2, seed: 2), record("A", revision: 2, seed: 3)])

        let hits = await cache.validEntries(for: [asset("A")], revision: 2)
        #expect(hits["A"]?.vector == vector(seed: 3))
        #expect(await cache.recordCount() == 1)
    }

    /// 450 records are written with three saves: 200, 200 and 50.
    @Test func upsertSavesEveryTwoHundredRecords() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let records = (0..<450).map { record("asset-\($0)", seed: $0) }
        try await cache.upsert(records)

        let store = try #require(await cache.openStore())
        #expect(SwiftDataFeaturePrintCache.writeBatchSize == 200)
        #expect(await store.saveCount == 3)
        #expect(await cache.recordCount() == 450)
    }

    /// A read larger than one fetch batch still returns every record.
    @Test func readsMoreAssetsThanOneFetchBatch() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let count = AnalysisStore.fetchBatchSize * 2 + 7
        try await cache.upsert((0..<count).map { record("asset-\($0)", seed: $0) })

        let hits = await cache.validEntries(for: (0..<count).map { asset("asset-\($0)") }, revision: 2)
        #expect(hits.count == count)
        #expect(hits["asset-\(count - 1)"]?.vector == vector(seed: count - 1))
    }

    /// Purging removes the given assets only; duplicates and unknown IDs are fine.
    @Test func purgeRemovesOnlyTheGivenAssets() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A"), record("B"), record("C")])
        try await cache.purge(assetIDs: ["A", "C", "C", "unknown"])

        let hits = await cache.validEntries(for: [asset("A"), asset("B"), asset("C")], revision: 2)
        #expect(Set(hits.keys) == ["B"])
        #expect(await cache.recordCount() == 1)
    }

    /// The full-diff fallback (SPS-10) lists every cached ID, of every revision, across more than one page.
    @Test func cachedAssetIDsListsEveryRecord() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        #expect(await cache.cachedAssetIDs().isEmpty)
        let ids = (0..<(AnalysisStore.fetchBatchSize + 7)).map { "asset-\($0)" }
        try await cache.upsert(ids.map { record($0, seed: 0) } + [record("old-revision", revision: 1)])
        #expect(await cache.cachedAssetIDs() == Set(ids + ["old-revision"]))

        try await cache.purge(assetIDs: ["asset-0"])
        #expect(await cache.cachedAssetIDs().contains("asset-0") == false)
    }

    /// Calls with nothing to do never open the store.
    @Test func emptyCallsDoNotOpenTheStore() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        #expect(await cache.validEntries(for: [], revision: 2).isEmpty)
        try await cache.upsert([])
        try await cache.purge(assetIDs: [])
        #expect(await cache.isOpened == false)
    }

    // MARK: - File store

    /// Records written by one cache are read by a new cache over the same directory.
    @Test func recordsSurviveReopeningTheStore() async throws {
        try await withTemporaryDirectory { directory in
            try await SwiftDataFeaturePrintCache(location: .directory(directory)).upsert([record("A")])

            let reopened = SwiftDataFeaturePrintCache(location: .directory(directory))
            let hits = await reopened.validEntries(for: [asset("A")], revision: 2)
            #expect(hits["A"] == record("A"))
            let storeFile = AnalysisContainerFactory.storeURL(in: directory)
            #expect(FileManager.default.fileExists(atPath: storeFile.path(percentEncoded: false)))
        }
    }

    /// The store directory is excluded from backup.
    @Test func theStoreDirectoryIsExcludedFromBackup() async throws {
        try await withTemporaryDirectory { directory in
            let cache = SwiftDataFeaturePrintCache(location: .directory(directory))
            try await cache.upsert([record("A")])

            let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
    }

    /// A store that is not a database is deleted and rebuilt as a working file store.
    @Test func aCorruptStoreIsDeletedAndRebuilt() async throws {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeFile = AnalysisContainerFactory.storeURL(in: directory)
            for file in AnalysisContainerFactory.storeFiles(at: storeFile) {
                try Data("this is not a SQLite database".utf8).write(to: file)
            }

            let cache = SwiftDataFeaturePrintCache(location: .directory(directory))
            #expect(await cache.validEntries(for: [asset("A")], revision: 2).isEmpty)
            try await cache.upsert([record("A")])

            // A new instance reads it back, so the rebuilt store is a real file again, not the in-memory fallback.
            let reopened = SwiftDataFeaturePrintCache(location: .directory(directory))
            #expect(await reopened.validEntries(for: [asset("A")], revision: 2)["A"] == record("A"))
        }
    }

    // MARK: - Migration

    /// A version 1 store opens as version 2 and keeps its feature prints; the old score is not carried over.
    @Test func aVersion1StoreMigratesWithoutLosingFeaturePrints() async throws {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeFile = AnalysisContainerFactory.storeURL(in: directory)
            let vectorData = FeatureVectorPacking.data(from: vector(seed: 1))
            try writeVersion1Store(at: storeFile) { context in
                context.insert(AnalysisSchemaV1.CachedAnalysis(
                    assetID: "A",
                    vectorData: vectorData,
                    revision: 2,
                    modificationDate: modificationDate,
                    qualityScore: 0.75,
                    status: AnalysisStatus.analyzed.rawValue,
                    analyzedAt: analyzedAt
                ))
            }

            let cache = SwiftDataFeaturePrintCache(location: .directory(directory))
            let hit = await cache.validEntries(for: [asset("A")], revision: 2)["A"]
            #expect(hit == record("A"))
            #expect(hit?.quality == nil)

            // The migrated store takes measurements.
            try await cache.upsert([record("A", quality: measurement)])
            let reopened = SwiftDataFeaturePrintCache(location: .directory(directory))
            #expect(await reopened.validEntries(for: [asset("A")], revision: 2)["A"]?.quality == measurement)
        }
    }

    /// The plan lists every version in order and migrates each to the next.
    @Test func theMigrationPlanCoversEveryVersion() {
        #expect(AnalysisMigrationPlan.schemas.map { $0.versionIdentifier } == [
            AnalysisSchemaV1.versionIdentifier,
            AnalysisSchemaV2.versionIdentifier
        ])
        #expect(AnalysisMigrationPlan.stages.count == AnalysisMigrationPlan.schemas.count - 1)
        #expect(AnalysisMigrationPlan.current.versionIdentifier == AnalysisSchemaV2.versionIdentifier)
    }

    /// Creates a version 1 store at `url`, as a build from before SPS-17 would have, and saves what `insert` adds.
    /// Rows are created inside `insert`, after the container exists (SwiftData needs it to build a model).
    private func writeVersion1Store(at url: URL, insert: (ModelContext) -> Void) throws {
        let schema = Schema(versionedSchema: AnalysisSchemaV1.self)
        let configuration = ModelConfiguration("Analysis", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        insert(context)
        try context.save()
    }

    // MARK: - Vector packing

    /// Packing and unpacking keeps every float bit for bit, including -0 and infinity.
    @Test func vectorsRoundTripBitForBit() throws {
        let values: [Float] = [0, -0.0, 1, -1, .leastNonzeroMagnitude, .greatestFiniteMagnitude, .infinity, 0.1]
        let data = FeatureVectorPacking.data(from: values)
        #expect(data.count == values.count * MemoryLayout<Float>.stride)
        let decoded = try #require(FeatureVectorPacking.vector(from: data))
        #expect(decoded.map(\.bitPattern) == values.map(\.bitPattern))
    }

    /// An empty vector (failed or skipped records) round-trips.
    @Test func anEmptyVectorRoundTrips() {
        #expect(FeatureVectorPacking.vector(from: FeatureVectorPacking.data(from: [])) == [])
    }

    /// A byte count that is not a multiple of 4 is rejected.
    @Test func bytesThatAreNotWholeFloatsAreRejected() {
        #expect(FeatureVectorPacking.vector(from: Data([1, 2, 3])) == nil)
    }

    /// A `Data` slice that starts at an odd offset decodes correctly.
    @Test func aMisalignedSliceDecodes() throws {
        let values: [Float] = [1.5, -2.25, 3.125]
        let padded = Data([0xFF]) + FeatureVectorPacking.data(from: values)
        let slice = padded.dropFirst()
        #expect(try #require(FeatureVectorPacking.vector(from: slice)) == values)
    }
}
