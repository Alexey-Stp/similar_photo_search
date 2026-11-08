import Foundation

/// A photo in the user's library, described without any PhotoKit types.
///
/// Instances are safe to pass across actor boundaries; `id` is the PhotoKit `localIdentifier`.
public struct PhotoAsset: Sendable, Hashable, Identifiable {
    /// The PhotoKit `localIdentifier` of the asset.
    public let id: String
    /// When the photo was taken, if known.
    public let creationDate: Date?
    /// When the asset was last modified (for example edited). Part of the feature-print cache key.
    public let modificationDate: Date?
    /// Width of the original image in pixels.
    public let pixelWidth: Int
    /// Height of the original image in pixels.
    public let pixelHeight: Int
    /// Whether the user marked the photo as a favorite. Favorites are never auto-selected for deletion.
    public let isFavorite: Bool
    /// Media subtypes of the photo.
    public let mediaSubtypes: Set<PhotoSubtype>
    /// Identifier shared by all photos of one burst, if the photo belongs to a burst.
    public let burstIdentifier: String?

    /// Creates a photo asset description.
    public init(
        id: String,
        creationDate: Date?,
        modificationDate: Date? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool,
        mediaSubtypes: Set<PhotoSubtype>,
        burstIdentifier: String? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.mediaSubtypes = mediaSubtypes
        self.burstIdentifier = burstIdentifier
    }
}
