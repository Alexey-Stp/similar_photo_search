import Domain
import Foundation
import SwiftData

/// Version 1 of the analysis cache schema (SPS-13). Frozen: never change its stored properties.
enum AnalysisSchemaV1: VersionedSchema {
    /// Version 1.0.0.
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// The models of this version.
    static var models: [any PersistentModel.Type] { [CachedAnalysis.self] }

    /// One analysed photo, as stored by version 1.
    @Model
    final class CachedAnalysis {
        /// The PhotoKit `localIdentifier`.
        @Attribute(.unique) var assetID: String
        /// The packed feature-print vector.
        var vectorData: Data
        /// The Vision request revision.
        var revision: Int
        /// `PHAsset.modificationDate` at analysis time.
        var modificationDate: Date?
        /// A normalized quality score; never written by any release, dropped in version 2.
        var qualityScore: Double?
        /// `AnalysisStatus.rawValue`.
        var status: String
        /// When the photo was analysed.
        var analyzedAt: Date

        /// Creates a version 1 row (used by the migration tests).
        init(
            assetID: String,
            vectorData: Data,
            revision: Int,
            modificationDate: Date?,
            qualityScore: Double?,
            status: String,
            analyzedAt: Date
        ) {
            self.assetID = assetID
            self.vectorData = vectorData
            self.revision = revision
            self.modificationDate = modificationDate
            self.qualityScore = qualityScore
            self.status = status
            self.analyzedAt = analyzedAt
        }
    }
}

/// Version 2 of the analysis cache schema (SPS-17): the raw quality measurement with its scoring version replaces
/// version 1's unused normalized `qualityScore`. Scores are normalized per cluster, so only raw values can be cached.
///
/// To change the model, add `AnalysisSchemaV3` with a copy of the model, point `CachedAnalysis` and
/// `AnalysisMigrationPlan.current` at it and add a stage to `AnalysisMigrationPlan`. Never edit a shipped version.
enum AnalysisSchemaV2: VersionedSchema {
    /// Version 2.0.0.
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    /// The models of this version.
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
        /// `AnalysisStatus.rawValue`: `analyzed`, `skipped` or `failed`.
        var status: String
        /// When the photo was analysed.
        var analyzedAt: Date
        /// `QualityMeasurement.version`; `nil` if the photo's quality was never measured. The other `quality*`
        /// fields are meaningful only when this is set.
        var qualityVersion: Int?
        /// `QualityMeasurement.sharpness` (raw Laplacian variance).
        var qualitySharpness: Float?
        /// `QualityMeasurement.faceQuality`; `nil` also when no face was found.
        var qualityFaceScore: Float?
        /// `QualityMeasurement.aesthetics`.
        var qualityAesthetics: Float?
        /// `QualityMeasurement.isUtility`.
        var qualityIsUtility: Bool?
        /// `QualityMeasurement.isEdited`.
        var qualityIsEdited: Bool?

        /// Creates the row of `record`.
        init(_ record: AnalysisRecord) {
            self.assetID = record.assetID
            self.vectorData = FeatureVectorPacking.data(from: record.vector)
            self.revision = record.revision
            self.modificationDate = record.assetModificationDate
            self.status = record.status.rawValue
            self.analyzedAt = record.analyzedAt
            self.qualityVersion = record.quality?.version
            self.qualitySharpness = record.quality?.sharpness
            self.qualityFaceScore = record.quality?.faceQuality
            self.qualityAesthetics = record.quality?.aesthetics
            self.qualityIsUtility = record.quality?.isUtility
            self.qualityIsEdited = record.quality?.isEdited
        }

        /// Overwrites every field except `assetID` with `record`'s.
        func update(from record: AnalysisRecord) {
            vectorData = FeatureVectorPacking.data(from: record.vector)
            revision = record.revision
            modificationDate = record.assetModificationDate
            status = record.status.rawValue
            analyzedAt = record.analyzedAt
            setQuality(record.quality)
        }

        /// The record this row holds, or `nil` if its status or vector bytes can't be decoded. An incomplete quality
        /// measurement (a version without sharpness or edit flag) drops only the measurement, not the record.
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
                quality: storedQuality,
                analyzedAt: analyzedAt
            )
        }

        /// The stored measurement, if complete.
        private var storedQuality: QualityMeasurement? {
            guard let qualityVersion, let qualitySharpness, let qualityIsEdited else { return nil }
            return QualityMeasurement(
                version: qualityVersion,
                sharpness: qualitySharpness,
                faceQuality: qualityFaceScore,
                aesthetics: qualityAesthetics,
                isUtility: qualityIsUtility,
                isEdited: qualityIsEdited
            )
        }

        /// Stores `quality`'s fields, or clears them all.
        private func setQuality(_ quality: QualityMeasurement?) {
            qualityVersion = quality?.version
            qualitySharpness = quality?.sharpness
            qualityFaceScore = quality?.faceQuality
            qualityAesthetics = quality?.aesthetics
            qualityIsUtility = quality?.isUtility
            qualityIsEdited = quality?.isEdited
        }
    }
}

/// The current analysis cache model.
typealias CachedAnalysis = AnalysisSchemaV2.CachedAnalysis

/// Migrations between analysis cache schema versions.
enum AnalysisMigrationPlan: SchemaMigrationPlan {
    /// The version every container is opened with.
    static var current: any VersionedSchema.Type { AnalysisSchemaV2.self }

    /// Every schema version, oldest first.
    static var schemas: [any VersionedSchema.Type] { [AnalysisSchemaV1.self, AnalysisSchemaV2.self] }

    /// The migration stages between neighbouring versions.
    ///
    /// V1 → V2 is lightweight: it drops `qualityScore` (never written) and adds optional `quality*` columns, so every
    /// cached feature print survives and no photo is analysed again.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AnalysisSchemaV1.self, toVersion: AnalysisSchemaV2.self)]
    }
}
