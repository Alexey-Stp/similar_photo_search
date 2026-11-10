import Foundation

/// One photo as the clustering engine sees it: when it was taken, its burst and its feature print.
public struct VectorItem: Sendable, Hashable, Identifiable {
    /// The PhotoKit `localIdentifier` of the photo.
    public let id: String
    /// When the photo was taken.
    public let date: Date
    /// `PhotoAsset.burstIdentifier`: photos of the same burst get `ClusteringConfig.burstSlack`.
    public let burstID: String?
    /// The Vision revision of `vector` (`FeaturePrint.revision`). Items of different revisions are never compared.
    public let revision: Int
    /// The feature-print vector.
    public let vector: [Float]

    /// Creates an item.
    public init(id: String, date: Date, burstID: String? = nil, revision: Int, vector: [Float]) {
        self.id = id
        self.date = date
        self.burstID = burstID
        self.revision = revision
        self.vector = vector
    }

    /// Creates an item from a photo and its feature print.
    ///
    /// Returns `nil` if the photo has no `creationDate` (it is never in a session) or the print belongs to another
    /// photo.
    public init?(asset: PhotoAsset, featurePrint: FeaturePrint) {
        guard let date = asset.creationDate, asset.id == featurePrint.assetID else { return nil }
        self.init(
            id: asset.id,
            date: date,
            burstID: asset.burstIdentifier,
            revision: featurePrint.revision,
            vector: featurePrint.vector
        )
    }
}
