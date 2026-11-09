import Domain
import Foundation
import SwiftData

/// Version 1 of the analysis cache schema.
///
/// To change the model, add `AnalysisSchemaV2` with a copy of the model, point `CachedAnalysis` at it and add a
/// stage to `AnalysisMigrationPlan`. Never edit a shipped version in place.
enum AnalysisSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [CachedAnalysis.self] }

    /// One analysed photo. No relationships, so bulk reads stay flat.
    @Model
    final class CachedAnalysis {
        /// The PhotoKit `localIdentifier`.
        @Attribute(.unique) var assetID: String
        /// The feature-print vector as packed native `Float`s (`FeatureVectorPacking`); empty unless `status` is
        /// `analyzed`. About 3 KB for Revision 2, small enough to stay inline (no `.externalStorage`).
        var vectorData: Data
        /// The Vision request revision.
        var revision: Int
        /// `PHAsset.modificationDate` at analysis time.
        var modificationDate: Date?
        /// Quality score (SPS-17), if computed.
        var qualityScore: Double?
        /// `AnalysisStatus.rawValue`: `analyzed`, `skipped` or `failed`.
        var status: String
        /// When the photo was analysed.
        var analyzedAt: Date

        /// Creates the row of `record`.
        init(_ record: AnalysisRecord) {
            self.assetID = record.assetID
            self.vectorData = FeatureVectorPacking.data(from: record.vector)
            self.revision = record.revision
            self.modificationDate = record.assetModificationDate
            self.qualityScore = record.qualityScore
            self.status = record.status.rawValue
            self.analyzedAt = record.analyzedAt
        }

        /// Overwrites every field except `assetID` with `record`'s.
        func update(from record: AnalysisRecord) {
            vectorData = FeatureVectorPacking.data(from: record.vector)
            revision = record.revision
            modificationDate = record.assetModificationDate
            qualityScore = record.qualityScore
            status = record.status.rawValue
            analyzedAt = record.analyzedAt
        }

        /// The record this row holds, or `nil` if its status or vector bytes can't be decoded.
        var record: AnalysisRecord? {
            guard let decodedStatus = AnalysisStatus(rawValue: status),
                  let vector = FeatureVectorPacking.vector(from: vectorData) else {
                return nil
            }
            return AnalysisRecord(
                assetID: assetID,
                revision: revision,
                assetModificationDate: modificationDate,
                status: decodedStatus,
                vector: vector,
                qualityScore: qualityScore,
                analyzedAt: analyzedAt
            )
        }
    }
}

/// The current analysis cache model.
typealias CachedAnalysis = AnalysisSchemaV1.CachedAnalysis

/// Migrations between analysis cache schema versions. Version 1 needs none.
enum AnalysisMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AnalysisSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
