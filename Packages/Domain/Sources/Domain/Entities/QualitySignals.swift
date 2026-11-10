import Foundation

/// Everything `QualityRanker` needs to know about one cluster member.
public struct QualitySignals: Sendable, Hashable {
    /// Variance of the Laplacian (raw); higher is sharper.
    public let sharpness: Float
    /// Mean face capture quality (0…1), or `nil` if no face was found.
    public let faceQuality: Float?
    /// Aesthetics `overallScore` (-1…1), or `nil` where not available.
    public let aesthetics: Float?
    /// Vision's `isUtility`, or `nil` where not available. Not weighted; kept for later rules.
    public let isUtility: Bool?
    /// Width × height of the original, in pixels.
    public let pixelCount: Int
    /// Whether the user marked the photo as a favorite. A favorite is always protected.
    public let isFavorite: Bool
    /// Whether the photo has edits.
    public let isEdited: Bool

    /// Creates signals.
    public init(
        sharpness: Float,
        faceQuality: Float? = nil,
        aesthetics: Float? = nil,
        isUtility: Bool? = nil,
        pixelCount: Int,
        isFavorite: Bool = false,
        isEdited: Bool = false
    ) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.pixelCount = pixelCount
        self.isFavorite = isFavorite
        self.isEdited = isEdited
    }

    /// Combines a (possibly cached) measurement with the photo's current metadata (resolution, favorite).
    public init(measurement: QualityMeasurement, asset: PhotoAsset) {
        self.init(
            sharpness: measurement.sharpness,
            faceQuality: measurement.faceQuality,
            aesthetics: measurement.aesthetics,
            isUtility: measurement.isUtility,
            pixelCount: max(0, asset.pixelWidth) * max(0, asset.pixelHeight),
            isFavorite: asset.isFavorite,
            isEdited: measurement.isEdited
        )
    }
}

/// How much each signal counts in the weighted quality score.
///
/// Weights need not sum to 1: the score divides by the sum of the weights of the signals used for the cluster, so
/// a signal that some member lacks hands its weight to the others in proportion to theirs. Negative weights count as 0.
public struct QualityWeights: Sendable, Hashable {
    /// Weight of sharpness.
    public var sharpness: Double
    /// Weight of face quality.
    public var faceQuality: Double
    /// Weight of resolution (pixel count).
    public var resolution: Double
    /// Weight of aesthetics.
    public var aesthetics: Double

    /// Creates weights.
    public init(sharpness: Double, faceQuality: Double, resolution: Double, aesthetics: Double) {
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.resolution = resolution
        self.aesthetics = aesthetics
    }

    /// The default: `0.4·sharpness + 0.4·faceQuality + 0.1·resolution + 0.1·aesthetics`.
    public static let standard = QualityWeights(sharpness: 0.4, faceQuality: 0.4, resolution: 0.1, aesthetics: 0.1)
}

/// Why a member ranks well. The raw value is the key of its text in `Localizable.xcstrings` (Presentation), never
/// an English string.
public enum QualityReason: String, Sendable, Hashable, CaseIterable {
    /// The user marked the photo as a favorite; it is protected whatever its score.
    case favorite = "quality.reason.favorite"
    /// The sharpest photo of the cluster.
    case sharpest = "quality.reason.sharpest"
    /// The best faces (open eyes, in focus, facing the camera) of the cluster.
    case bestFaces = "quality.reason.bestFaces"
    /// The highest resolution of the cluster.
    case highestResolution = "quality.reason.highestResolution"
    /// The best aesthetics score of the cluster.
    case bestAesthetics = "quality.reason.bestAesthetics"
}

/// One cluster member with its weighted quality score.
public struct RankedMember: Sendable, Hashable {
    /// The PhotoKit `localIdentifier`.
    public let assetID: String
    /// Weighted score in 0…1, normalized within the cluster; higher is better. Only comparable within one cluster.
    public let score: Double
    /// Whether the photo must never be auto-selected for deletion (it is a favorite), whatever its score.
    public let isProtected: Bool
    /// Why the member ranks well, for the UI.
    public let reasons: [QualityReason]

    /// Creates a ranked member.
    public init(assetID: String, score: Double, isProtected: Bool, reasons: [QualityReason]) {
        self.assetID = assetID
        self.score = score
        self.isProtected = isProtected
        self.reasons = reasons
    }
}
