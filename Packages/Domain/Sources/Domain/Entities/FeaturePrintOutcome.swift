import Foundation

/// Why the analysis of a photo failed after its image was loaded.
///
/// Unlike a `SkipReason`, a failure is a problem with the analysis itself. The photo is left out of comparison and the
/// scan goes on with the next photo.
public enum AnalysisFailure: String, Sendable, Hashable, Codable, CaseIterable {
    /// Vision could not compute a feature print, for example because the image is too small.
    case vision
}

/// The result of computing the feature print of one photo.
public enum FeaturePrintOutcome: Sendable, Hashable {
    /// The feature print was computed.
    case computed(FeaturePrint)
    /// The image could not be loaded, so Vision never ran (for example an iCloud-only original).
    case skipped(SkipReason)
    /// The image was loaded but the analysis failed.
    case failed(AnalysisFailure)

    /// The computed feature print, or `nil` for a skipped or failed photo.
    public var featurePrint: FeaturePrint? {
        if case .computed(let featurePrint) = self {
            return featurePrint
        }
        return nil
    }
}
