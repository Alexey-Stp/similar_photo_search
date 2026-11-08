import Foundation

/// An album the user can pick as scan scope.
public struct AlbumSummary: Sendable, Hashable, Identifiable {
    /// The PhotoKit `localIdentifier` of the album.
    public let id: String
    /// The album's localized title as shown in Photos. May be empty; then derive one from `kind`.
    public let title: String
    /// What kind of album this is.
    public let kind: AlbumKind
    /// Approximate number of items in the album. It is an estimate and may include videos.
    public let estimatedCount: Int

    /// Creates an album summary.
    public init(id: String, title: String, kind: AlbumKind, estimatedCount: Int) {
        self.id = id
        self.title = title
        self.kind = kind
        self.estimatedCount = estimatedCount
    }
}

/// Kinds of albums offered as scan scope.
public enum AlbumKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// The Favorites smart album.
    case favorites
    /// The Recents smart album (the whole library).
    case recents
    /// The Selfies smart album.
    case selfies
    /// The Portrait smart album.
    case portrait
    /// An album the user created.
    case user
}
