#if DEBUG
import Domain
import Foundation

/// Fixed-content `PhotoLibraryRepository` for SwiftUI previews. It never touches PhotoKit.
struct PreviewPhotoLibraryRepository: PhotoLibraryRepository {
    /// Albums returned by `albums()`.
    let albumList: [AlbumSummary]
    /// Count returned for All Photos.
    let libraryCount: Int

    /// The sum of the selected albums' counts, or `libraryCount` for All Photos.
    func assetCount(scope: ScanScope) async -> Int {
        guard let ids = scope.albumIDs else { return libraryCount }
        return albumList.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.estimatedCount }
    }

    /// An empty stream; previews never scan.
    func assetPages(scope: ScanScope, pageSize: Int) -> AsyncThrowingStream<[PhotoAsset], Error> {
        AsyncThrowingStream { $0.finish() }
    }

    /// Returns `albumList`.
    func albums() async -> [AlbumSummary] { albumList }

    /// A typical small library with smart and user albums.
    static let sample = PreviewPhotoLibraryRepository(
        albumList: [
            AlbumSummary(id: "recents", title: "Recents", kind: .recents, estimatedCount: 4_210),
            AlbumSummary(id: "favorites", title: "Favorites", kind: .favorites, estimatedCount: 87),
            AlbumSummary(id: "selfies", title: "Selfies", kind: .selfies, estimatedCount: 312),
            AlbumSummary(id: "trip", title: "Lisbon 2026", kind: .user, estimatedCount: 640),
            AlbumSummary(id: "family", title: "Family", kind: .user, estimatedCount: 1)
        ],
        libraryCount: 4_210
    )
}

/// `ScopePreferencesStore` for previews: starts from the given value and forgets what is saved.
struct PreviewScopePreferencesStore: ScopePreferencesStore {
    let preferences: ScopePreferences

    func load() async -> ScopePreferences { preferences }
    func save(_ preferences: ScopePreferences) async {}
}

extension ScopeSelectionViewModel {
    /// A view model over `PreviewPhotoLibraryRepository.sample`.
    static func preview(
        preferences: ScopePreferences = ScopePreferences(albumIDs: ["trip"], dateFilter: .thisYear)
    ) -> ScopeSelectionViewModel {
        ScopeSelectionViewModel(
            library: PreviewPhotoLibraryRepository.sample,
            store: PreviewScopePreferencesStore(preferences: preferences)
        )
    }
}
#endif
