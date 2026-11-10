import Foundation

/// The raw, per-photo quality signals that are expensive to compute (they need the image and Vision).
///
/// Values are **raw**, not normalized: scores are min-max normalized within a cluster (`QualityRanker`), so a
/// normalized score would be wrong as soon as the cluster changes. That makes a measurement safe to cache
/// (`AnalysisRecord.quality`). It is stale when `version` differs from `QualityScorer.scoringVersion`.
///
/// Cheap metadata (`pixelCount`, `isFavorite`) is not part of it: it comes from the current `PhotoAsset` when the
/// cluster is ranked (`QualitySignals(measurement:asset:)`), so a favorite added later is never missed.
public struct QualityMeasurement: Sendable, Hashable {
    /// The scoring version the photo was measured with (`QualityScorer.scoringVersion`).
    public let version: Int
    /// Variance of the Laplacian of the grayscale analysis image; higher is sharper. Only comparable between photos
    /// measured with the same `version`.
    public let sharpness: Float
    /// Mean Vision face capture quality (0…1) over the detected faces, or `nil` if no face was found (never 0 for
    /// "no faces").
    public let faceQuality: Float?
    /// Vision aesthetics `overallScore` (-1…1), or `nil` where it is not available (before iOS 18).
    public let aesthetics: Float?
    /// Vision's `isUtility` (screenshot, receipt, document), or `nil` where aesthetics are not available.
    public let isUtility: Bool?
    /// Whether the photo has edits (adjustment data in Photos).
    public let isEdited: Bool

    /// Creates a measurement.
    public init(
        version: Int,
        sharpness: Float,
        faceQuality: Float?,
        aesthetics: Float?,
        isUtility: Bool?,
        isEdited: Bool
    ) {
        self.version = version
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.isEdited = isEdited
    }
}

/// The result of measuring the quality of one photo.
public enum QualityOutcome: Sendable, Hashable {
    /// The photo was measured.
    case measured(QualityMeasurement)
    /// The image could not be loaded (or the photo is gone), so nothing ran.
    case skipped(SkipReason)
    /// The image was loaded but the analysis failed.
    case failed(AnalysisFailure)

    /// The measurement, or `nil` for a skipped or failed photo.
    public var measurement: QualityMeasurement? {
        if case .measured(let measurement) = self {
            return measurement
        }
        return nil
    }
}
