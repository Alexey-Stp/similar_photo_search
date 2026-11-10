import Foundation

/// The clusters of one analysed session, saved so the next scan can reuse them when the session has not changed.
///
/// Only sessions of two or more photos are stored, also those without any cluster (so an unchanged session costs
/// nothing next time). The keeper suggestion is not stored: it is recomputed from the cached quality measurements
/// and the photos' current favorite flags on every scan.
public struct StoredSessionResult: Sendable, Hashable {
    /// The session's membership when it was analysed. Its `sessionID` is the key of the stored result.
    public let fingerprint: SessionFingerprint
    /// The session's clusters, newest first, without `suggestedKeeperID`.
    public let clusters: [SimilarityCluster]
    /// `ScanResultsKey.value` of the settings the clusters were computed with. A result with another key is stale.
    public let resultsKey: String

    /// Creates a result.
    public init(fingerprint: SessionFingerprint, clusters: [SimilarityCluster], resultsKey: String) {
        self.fingerprint = fingerprint
        self.clusters = clusters
        self.resultsKey = resultsKey
    }

    /// `PhotoSession.id` of the session.
    public var sessionID: String { fingerprint.sessionID }
}

/// Names everything that decides which clusters a session gets, apart from its photos: the session config, the
/// clustering config and the feature-print revision. Stored clusters are reused only under the same key, so changing
/// the session gap, a threshold or the Vision revision recomputes every cluster (cached feature prints stay valid).
public struct ScanResultsKey: Sendable, Hashable {
    /// The stable textual key. Deterministic across launches.
    public let value: String

    /// The key for these settings.
    public init(sessionConfig: SessionConfig, clusteringConfig: ClusteringConfig, revision: Int) {
        let thresholds = clusteringConfig.thresholds
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.bitPattern)" }
            .joined(separator: ",")
        value = [
            "v1",
            "gap=\(sessionConfig.sessionGap.bitPattern)",
            "max=\(sessionConfig.maxSessionSize)",
            "rev=\(revision)",
            "thr=\(thresholds)",
            "pair=\(clusteringConfig.maxPairInterval.bitPattern)",
            "chain=\(clusteringConfig.maxChainSize)",
            "burst=\(clusteringConfig.burstSlack.bitPattern)",
            "link=\(clusteringConfig.chainLinkageSlack.bitPattern)",
            "exact=\(clusteringConfig.exactDuplicateDistance.bitPattern)"
        ].joined(separator: ";")
    }
}
