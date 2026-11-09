@testable import DataLayer
import Domain
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SwiftDataFeaturePrintCacheTests {
    /// Sub-second on purpose: the date must survive the SQLite round trip exactly.
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000.123_456)
    private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_500.5)

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

    /// A Revision 2 sized vector whose values depend on `seed`.
    private func vector(seed: Int, count: Int = 768) -> [Float] {
        (0..<count).map { Float(seed) + Float($0) / 1_000 }
    }

    private func record(_ id: String, revision: Int = 2, seed: Int = 1, qualityScore: Double? = nil) -> AnalysisRecord {
        AnalysisRecord(
            featurePrint: FeaturePrint(
                assetID: id,
                revision: revision,
                vector: vector(seed: seed),
                assetModificationDate: modificationDate
            ),
            qualityScore: qualityScore,
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

    @Test func storedRecordsComeBackUnchanged() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let analyzed = record("A", qualityScore: 0.75)
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

    @Test func aDifferentRevisionIsAMiss() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A", revision: 1)])
        #expect(await cache.validEntries(for: [asset("A")], revision: 2).isEmpty)
        #expect(await cache.validEntries(for: [asset("A")], revision: 1).count == 1)
    }

    @Test func aModifiedPhotoIsAMiss() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A")])
        let edited = asset("A", modified: modificationDate.addingTimeInterval(1))
        #expect(await cache.validEntries(for: [edited], revision: 2).isEmpty)
    }

    @Test func unknownAssetsAreMisses() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A")])
        let hits = await cache.validEntries(for: [asset("A"), asset("unknown")], revision: 2)
        #expect(Set(hits.keys) == ["A"])
    }

    // MARK: - Writes

    @Test func upsertReplacesTheRecordOfTheSameAsset() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A", revision: 1, seed: 1)])
        try await cache.upsert([record("A", revision: 2, seed: 2), record("A", revision: 2, seed: 3)])

        let hits = await cache.validEntries(for: [asset("A")], revision: 2)
        #expect(hits["A"]?.vector == vector(seed: 3))
        #expect(await cache.recordCount() == 1)
    }

    @Test func upsertSavesEveryTwoHundredRecords() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let records = (0..<450).map { record("asset-\($0)", seed: $0) }
        try await cache.upsert(records)

        let store = try #require(await cache.openStore())
        #expect(SwiftDataFeaturePrintCache.writeBatchSize == 200)
        #expect(await store.saveCount == 3)
        #expect(await cache.recordCount() == 450)
    }

    @Test func readsMoreAssetsThanOneFetchBatch() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        let count = AnalysisStore.fetchBatchSize * 2 + 7
        try await cache.upsert((0..<count).map { record("asset-\($0)", seed: $0) })

        let hits = await cache.validEntries(for: (0..<count).map { asset("asset-\($0)") }, revision: 2)
        #expect(hits.count == count)
        #expect(hits["asset-\(count - 1)"]?.vector == vector(seed: count - 1))
    }

    @Test func purgeRemovesOnlyTheGivenAssets() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        try await cache.upsert([record("A"), record("B"), record("C")])
        try await cache.purge(assetIDs: ["A", "C", "C", "unknown"])

        let hits = await cache.validEntries(for: [asset("A"), asset("B"), asset("C")], revision: 2)
        #expect(Set(hits.keys) == ["B"])
        #expect(await cache.recordCount() == 1)
    }

    @Test func emptyCallsDoNotOpenTheStore() async throws {
        let cache = SwiftDataFeaturePrintCache(location: .inMemory)
        #expect(await cache.validEntries(for: [], revision: 2).isEmpty)
        try await cache.upsert([])
        try await cache.purge(assetIDs: [])
        #expect(await cache.isOpened == false)
    }

    // MARK: - File store

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

    @Test func theStoreDirectoryIsExcludedFromBackup() async throws {
        try await withTemporaryDirectory { directory in
            let cache = SwiftDataFeaturePrintCache(location: .directory(directory))
            try await cache.upsert([record("A")])

            let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
    }

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

    // MARK: - Vector packing

    @Test func vectorsRoundTripBitForBit() throws {
        let values: [Float] = [0, -0.0, 1, -1, .leastNonzeroMagnitude, .greatestFiniteMagnitude, .infinity, 0.1]
        let data = FeatureVectorPacking.data(from: values)
        #expect(data.count == values.count * MemoryLayout<Float>.stride)
        let decoded = try #require(FeatureVectorPacking.vector(from: data))
        #expect(decoded.map(\.bitPattern) == values.map(\.bitPattern))
    }

    @Test func anEmptyVectorRoundTrips() {
        #expect(FeatureVectorPacking.vector(from: FeatureVectorPacking.data(from: [])) == [])
    }

    @Test func bytesThatAreNotWholeFloatsAreRejected() {
        #expect(FeatureVectorPacking.vector(from: Data([1, 2, 3])) == nil)
    }

    @Test func aMisalignedSliceDecodes() throws {
        let values: [Float] = [1.5, -2.25, 3.125]
        let padded = Data([0xFF]) + FeatureVectorPacking.data(from: values)
        let slice = padded.dropFirst()
        #expect(try #require(FeatureVectorPacking.vector(from: slice)) == values)
    }
}
