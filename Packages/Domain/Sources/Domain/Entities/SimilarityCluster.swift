import Foundation

/// A group of visually similar photos from one shooting session.
public struct SimilarityCluster: Sendable, Hashable, Identifiable {
    /// Stable identifier of the cluster: by default its newest photo's `localIdentifier`.
    ///
    /// A photo belongs to at most one cluster per scan, so the ID is unique within a scan, and the same input always
    /// gives the same ID (unlike a random UUID).
    public let id: String
    /// `localIdentifier`s of the photos, in `PhotoAsset.libraryOrder` (newest first, ties by ID).
    public let assetIDs: [String]
    /// The photo suggested to keep, if one was chosen.
    public let suggestedKeeperID: String?
    /// Mean Euclidean feature-print distance over all pairs of photos in the cluster. Lower means more alike;
    /// use it as the confidence for sorting in the UI. Only comparable between clusters of the same revision.
    public let averageDistance: Float
    /// Whether every pair in the cluster is within `ClusteringConfig.exactDuplicateDistance`: copies of the same image.
    public let isExactDuplicate: Bool

    /// Creates a cluster. `id` defaults to the first of `assetIDs`.
    public init(
        id: String? = nil,
        assetIDs: [String],
        suggestedKeeperID: String? = nil,
        averageDistance: Float = 0,
        isExactDuplicate: Bool = false
    ) {
        self.id = id ?? assetIDs.first ?? ""
        self.assetIDs = assetIDs
        self.suggestedKeeperID = suggestedKeeperID
        self.averageDistance = averageDistance
        self.isExactDuplicate = isExactDuplicate
    }
}
