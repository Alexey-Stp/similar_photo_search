import Foundation

/// A group of visually similar photos found during a scan.
public struct SimilarityCluster: Sendable, Hashable, Identifiable {
    /// Stable identifier of the cluster for the lifetime of a scan.
    public let id: UUID
    /// `localIdentifier`s of the photos in the cluster.
    public let assetIDs: [String]
    /// The photo suggested to keep, if one was chosen.
    public let suggestedKeeperID: String?

    /// Creates a cluster.
    public init(id: UUID = UUID(), assetIDs: [String], suggestedKeeperID: String? = nil) {
        self.id = id
        self.assetIDs = assetIDs
        self.suggestedKeeperID = suggestedKeeperID
    }
}
