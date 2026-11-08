import Foundation

/// A photo in the user's library, described without any PhotoKit types.
///
/// Instances are safe to pass across actor boundaries; `id` is the PhotoKit `localIdentifier`.
public struct PhotoAsset: Sendable, Hashable, Identifiable {
    /// The PhotoKit `localIdentifier` of the asset.
    public let id: String
    /// When the photo was taken, if known.
    public let creationDate: Date?
    /// Width of the original image in pixels.
    public let pixelWidth: Int
    /// Height of the original image in pixels.
    public let pixelHeight: Int
    /// Whether the user marked the photo as a favorite. Favorites are never auto-selected for deletion.
    public let isFavorite: Bool
    /// Media subtypes of the photo.
    public let mediaSubtypes: Set<PhotoSubtype>

    /// Creates a photo asset description.
    public init(
        id: String,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool,
        mediaSubtypes: Set<PhotoSubtype>
    ) {
        self.id = id
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.mediaSubtypes = mediaSubtypes
    }
}
