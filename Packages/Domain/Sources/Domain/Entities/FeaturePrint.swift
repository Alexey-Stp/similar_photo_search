import Foundation

/// A Vision image feature print for one photo, stored as raw floats together with its Vision revision.
public struct FeaturePrint: Sendable, Hashable {
    /// The PhotoKit `localIdentifier` of the photo.
    public let assetID: String
    /// The Vision request revision that produced `vector`.
    public let revision: Int
    /// The feature-print vector.
    public let vector: [Float]
    /// `PHAsset.modificationDate` at the time the print was computed; used to invalidate the cache.
    public let assetModificationDate: Date?

    /// Creates a feature print.
    public init(assetID: String, revision: Int, vector: [Float], assetModificationDate: Date?) {
        self.assetID = assetID
        self.revision = revision
        self.vector = vector
        self.assetModificationDate = assetModificationDate
    }

    /// Whether the two prints can be compared: same Vision revision and same vector length.
    ///
    /// Vectors of different revisions must never be compared.
    public func isComparable(with other: FeaturePrint) -> Bool {
        revision == other.revision && vector.count == other.vector.count
    }
}
