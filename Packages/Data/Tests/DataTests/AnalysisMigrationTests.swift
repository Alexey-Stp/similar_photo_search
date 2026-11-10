@testable import DataLayer
import Domain
import Foundation
import SwiftData
import Testing

extension AnalysisStoreSuites {
    /// Migrations of the analysis cache store between schema versions.
    @Suite(.timeLimit(.minutes(1)))
    struct AnalysisMigrationTests {
        private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000.123_456)
        private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_500.5)
        private let vector: [Float] = (0..<768).map { 1 + Float($0) / 1_000 }
        private let measurement = QualityMeasurement(
            version: 1_031,
            sharpness: 0.012_5,
            faceQuality: 0.62,
            aesthetics: -0.3,
            isUtility: false,
            isEdited: true
        )

        /// Photo `A`, modified at `modificationDate`.
        private var asset: PhotoAsset {
            PhotoAsset(
                id: "A",
                creationDate: modificationDate,
                modificationDate: modificationDate,
                pixelWidth: 4_032,
                pixelHeight: 3_024,
                isFavorite: false,
                mediaSubtypes: []
            )
        }

        /// The analyzed record of photo `A`, with `quality` if given.
        private func record(quality: QualityMeasurement? = nil) -> AnalysisRecord {
            AnalysisRecord(
                featurePrint: FeaturePrint(
                    assetID: "A",
                    revision: 2,
                    vector: vector,
                    assetModificationDate: modificationDate
                ),
                quality: quality,
                analyzedAt: analyzedAt
            )
        }

        /// A version 1 store opens as version 2 and keeps its feature prints; the old score is not carried over.
        @Test func aVersion1StoreMigratesWithoutLosingFeaturePrints() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "AnalysisMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let vectorData = FeatureVectorPacking.data(from: vector)
            try writeVersion1Store(at: AnalysisContainerFactory.storeURL(in: directory)) { context in
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
            let hit = await cache.validEntries(for: [asset], revision: 2)["A"]
            #expect(hit == record())
            #expect(hit?.quality == nil)

            // The migrated store takes measurements.
            try await cache.upsert([record(quality: measurement)])
            let reopened = SwiftDataFeaturePrintCache(location: .directory(directory))
            #expect(await reopened.validEntries(for: [asset], revision: 2)["A"]?.quality == measurement)
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
    }
}
