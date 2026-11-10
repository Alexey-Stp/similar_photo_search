import Foundation

/// Parameters of the similarity clustering of one shooting session.
///
/// Changing the config changes the clusters, but not the feature prints: the cache stays valid.
public struct ClusteringConfig: Sendable, Hashable {
    /// Default `maxPairInterval`: 60 minutes.
    public static let defaultMaxPairInterval: TimeInterval = 60 * 60
    /// Default `maxChainSize`: 12 photos.
    public static let defaultMaxChainSize = 12
    /// Default `burstSlack`: burst photos may be 10 % further apart than the threshold.
    public static let defaultBurstSlack: Float = 1.1
    /// Default `chainLinkageSlack`: every pair of a re-clustered component must be within 115 % of the threshold.
    public static let defaultChainLinkageSlack: Float = 1.15
    /// Default `exactDuplicateDistance`: float noise only, so only identical images count.
    public static let defaultExactDuplicateDistance: Float = 1e-4

    /// The largest Euclidean feature-print distance that still makes two photos similar, keyed by Vision revision.
    ///
    /// Distances of different revisions have different scales, so a threshold only ever applies to its revision.
    /// Thresholds are calibrated on the labelled fixture set, never guessed.
    public var thresholds: [Int: Float]
    /// Two photos are compared only if they were taken at most this far apart (inclusive), so long sessions stay cheap.
    public var maxPairInterval: TimeInterval
    /// Connected components larger than this are re-clustered with complete linkage (the chaining guard).
    public var maxChainSize: Int
    /// Factor on the threshold for two photos of the same burst.
    public var burstSlack: Float
    /// Factor on the (burst-adjusted) threshold that every pair of a re-clustered component must stay within.
    public var chainLinkageSlack: Float
    /// Clusters whose pairs are all at most this far apart are flagged `SimilarityCluster.isExactDuplicate`.
    public var exactDuplicateDistance: Float

    /// Creates a config.
    public init(
        thresholds: [Int: Float],
        maxPairInterval: TimeInterval = defaultMaxPairInterval,
        maxChainSize: Int = defaultMaxChainSize,
        burstSlack: Float = defaultBurstSlack,
        chainLinkageSlack: Float = defaultChainLinkageSlack,
        exactDuplicateDistance: Float = defaultExactDuplicateDistance
    ) {
        self.thresholds = thresholds
        self.maxPairInterval = maxPairInterval
        self.maxChainSize = maxChainSize
        self.burstSlack = burstSlack
        self.chainLinkageSlack = chainLinkageSlack
        self.exactDuplicateDistance = exactDuplicateDistance
    }

    /// The threshold for vectors of `revision`, or `nil` if none was calibrated.
    public func threshold(forRevision revision: Int) -> Float? {
        thresholds[revision]
    }
}

/// Why a session could not be clustered.
public enum ClusteringError: Error, Sendable, Hashable {
    /// The session has at least two items of this revision, but `ClusteringConfig.thresholds` has no entry for it.
    case missingThreshold(revision: Int)
}
