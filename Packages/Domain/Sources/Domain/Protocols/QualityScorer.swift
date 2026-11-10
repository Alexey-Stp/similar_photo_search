import Foundation

/// Measures the raw quality signals of a photo (sharpness, faces, aesthetics, edits), so the best photo of a cluster
/// can be suggested as the keeper. The implementation loads the image itself; Domain never sees pixels.
///
/// Call it lazily, only for photos that ended up in a cluster. Rank a cluster with `QualityRanker` on
/// `QualitySignals(measurement:asset:)`; cache the measurement (not the ranked score) in `AnalysisRecord.quality`.
public protocol QualityScorer: Sendable {
    /// The version new measurements get. A cached measurement of another version is stale and must be measured again
    /// (`AnalysisRecord.quality(scoringVersion:)`). It changes with the algorithm and with the Vision requests the
    /// OS offers (for example aesthetics from iOS 18 on).
    var scoringVersion: Int { get }

    /// Measures one photo.
    ///
    /// A photo whose image can't be loaded is `.skipped`, and a photo that can't be analysed is `.failed`; neither
    /// throws, so a scan goes on with the next photo.
    /// - Throws: `CancellationError` if the calling task was cancelled. Nothing else.
    func measure(_ asset: PhotoAsset) async throws -> QualityOutcome
}
