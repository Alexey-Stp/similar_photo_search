import Foundation

/// Read access to the user's photo library.
///
/// Authorization lives in `PhotoPermissionService`.
///
/// Guarantees shared by every method:
/// - only images are returned; hidden assets never are;
/// - under limited access, only the photos the user shared are visible;
/// - no pixel data is loaded.
public protocol PhotoLibraryRepository: Sendable {
    /// Number of photos in `scope`, without loading them.
    ///
    /// Exact for the whole library or a single album. When several albums overlap,
    /// shared photos are counted once per album, so the value is an upper bound.
    func assetCount(scope: ScanScope) async -> Int

    /// Streams the photos in `scope` page by page.
    ///
    /// Order is a hard contract: `PhotoAsset.libraryOrder` (newest first, ties by `id`,
    /// photos without a date last). Each asset is delivered once, even if it is in several selected albums.
    /// Pages hold about `pageSize` assets; a page grows past it only to keep photos with
    /// the same timestamp together. Pages are produced on demand, and cancelling the consuming task stops the stream.
    func assetPages(scope: ScanScope, pageSize: Int) -> AsyncThrowingStream<[PhotoAsset], Error>

    /// Albums the user can choose as scan scope: Favorites, Recents, Selfies, Portrait and the user's own albums.
    func albums() async -> [AlbumSummary]

    /// The photos with these `localIdentifier`s that still exist, in `PhotoAsset.libraryOrder`, each once.
    ///
    /// Burst members are found too. A photo that was deleted (or is hidden, or no longer shared under limited
    /// access) is missing from the result, so callers can tell which of their IDs are gone.
    func assets(withIDs assetIDs: [String]) async -> [PhotoAsset]
}
