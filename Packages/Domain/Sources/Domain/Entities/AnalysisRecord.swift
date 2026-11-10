import Foundation

/// How the analysis of a cached photo ended.
public enum AnalysisStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Vision computed a feature print; the record carries its vector.
    case analyzed
    /// The image could not be loaded, so Vision never ran. `AnalysisRecord(outcome:asset:analyzedAt:)` never
    /// produces this status (see there); it exists so the stored status can name every outcome.
    case skipped
    /// The image was loaded but Vision failed. Cached so the photo is not run through Vision again on every scan.
    case failed
}

/// What the analysis cache remembers about one photo: a value type, safe to pass across actors.
///
/// A record is valid for a photo only if the asset ID, the Vision revision and the photo's modification date all
/// match (`isValid(for:revision:)`). Otherwise the photo is analysed again.
public struct AnalysisRecord: Sendable, Hashable {
    /// The PhotoKit `localIdentifier` of the photo.
    public let assetID: String
    /// The Vision request revision the photo was analysed with.
    public let revision: Int
    /// `PHAsset.modificationDate` at the time of the analysis.
    public let assetModificationDate: Date?
    /// How the analysis ended.
    public let status: AnalysisStatus
    /// The feature-print vector; empty unless `status` is `.analyzed`.
    public let vector: [Float]
    /// The photo's raw quality signals, once measured (SPS-17). Raw, not normalized: scores are normalized per
    /// cluster when ranked. Check its version with `quality(scoringVersion:)` before using it.
    public let quality: QualityMeasurement?
    /// When the photo was analysed.
    public let analyzedAt: Date

    /// Creates a record.
    public init(
        assetID: String,
        revision: Int,
        assetModificationDate: Date?,
        status: AnalysisStatus,
        vector: [Float] = [],
        quality: QualityMeasurement? = nil,
        analyzedAt: Date
    ) {
        self.assetID = assetID
        self.revision = revision
        self.assetModificationDate = assetModificationDate
        self.status = status
        self.vector = vector
        self.quality = quality
        self.analyzedAt = analyzedAt
    }

    /// Creates the record of a computed feature print.
    public init(featurePrint: FeaturePrint, quality: QualityMeasurement? = nil, analyzedAt: Date) {
        self.init(
            assetID: featurePrint.assetID,
            revision: featurePrint.revision,
            assetModificationDate: featurePrint.assetModificationDate,
            status: .analyzed,
            vector: featurePrint.vector,
            quality: quality,
            analyzedAt: analyzedAt
        )
    }

    /// Creates the record to cache for an outcome of `FeaturePrintService`, or `nil` if the outcome must not be cached.
    ///
    /// - `.computed` gives an `.analyzed` record with the print's own revision and modification date.
    /// - `.failed` gives a `.failed` record with `revision` (the service's current revision) and the photo's
    ///   modification date, so the photo is retried only after an edit or a new revision.
    /// - `.skipped` gives `nil`: a skip is cheap to find again (a local-only image request fails at once) and can
    ///   go away without the photo's modification date changing, for example when an iCloud-only original is
    ///   downloaded by the Photos app.
    public init?(outcome: FeaturePrintOutcome, asset: PhotoAsset, revision: Int, analyzedAt: Date) {
        switch outcome {
        case .computed(let featurePrint):
            self.init(featurePrint: featurePrint, analyzedAt: analyzedAt)
        case .failed:
            self.init(
                assetID: asset.id,
                revision: revision,
                assetModificationDate: asset.modificationDate,
                status: .failed,
                analyzedAt: analyzedAt
            )
        case .skipped:
            return nil
        }
    }

    /// The feature print, if the photo was analysed.
    public var featurePrint: FeaturePrint? {
        guard status == .analyzed else { return nil }
        return FeaturePrint(
            assetID: assetID,
            revision: revision,
            vector: vector,
            assetModificationDate: assetModificationDate
        )
    }

    /// The quality measurement if it was made with `scoringVersion`, otherwise `nil` (measure the photo again).
    ///
    /// Only meaningful on a record that `isValid(for:revision:)`: an edit to the photo invalidates the whole record.
    public func quality(scoringVersion: Int) -> QualityMeasurement? {
        guard let quality, quality.version == scoringVersion else { return nil }
        return quality
    }

    /// A copy of this record with `quality` replaced; everything else, including `analyzedAt`, is kept.
    public func withQuality(_ quality: QualityMeasurement?) -> AnalysisRecord {
        AnalysisRecord(
            assetID: assetID,
            revision: revision,
            assetModificationDate: assetModificationDate,
            status: status,
            vector: vector,
            quality: quality,
            analyzedAt: analyzedAt
        )
    }

    /// Whether this record still describes `asset`: same asset ID, `revision` and modification date.
    ///
    /// Every `FeaturePrintCache` applies this rule; a photo whose record is not valid is analysed again.
    public func isValid(for asset: PhotoAsset, revision: Int) -> Bool {
        assetID == asset.id && self.revision == revision && assetModificationDate == asset.modificationDate
    }
}
