import Domain
import Foundation
import os
import Photos

/// PhotoKit-backed `PhotoLibraryRepository`.
///
/// Holds no state: every call builds fresh, lazy `PHFetchResult`s, and no `PHAsset` leaves this file.
/// Only metadata is read; pixel data is never loaded here.
public final class PhotoKitLibraryRepository: PhotoLibraryRepository {
    private static let logger = Logger(subsystem: "com.similarphotos", category: "library")

    /// Smart albums offered as scan scope, in display order.
    private static let smartAlbums: [(subtype: PHAssetCollectionSubtype, kind: AlbumKind)] = [
        (.smartAlbumUserLibrary, .recents),
        (.smartAlbumFavorites, .favorites),
        (.smartAlbumSelfPortraits, .selfies),
        (.smartAlbumDepthEffect, .portrait)
    ]

    /// Creates the repository.
    public init() {}

    /// Number of photos in `scope`: the sum of one lazy fetch count per selected album, or the library count.
    public func assetCount(scope: ScanScope) async -> Int {
        // Fetch results are lazy: counting loads no assets.
        Self.fetchResults(for: scope).reduce(0) { $0 + $1.count }
    }

    /// Streams the photos in `scope` in `PhotoAsset.libraryOrder`. The fetches run when the first page is requested.
    public func assetPages(scope: ScanScope, pageSize: Int) -> AsyncThrowingStream<[PhotoAsset], Error> {
        AssetPageProducer.stream(pageSize: pageSize) {
            Self.fetchResults(for: scope).map { PHFetchResultSource(result: $0) as any AssetSource }
        }
    }

    /// Recents, Favorites, Selfies and Portrait (those that exist on this device), then the user's albums.
    public func albums() async -> [AlbumSummary] {
        var summaries: [AlbumSummary] = []
        for album in Self.smartAlbums {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: album.subtype,
                options: nil
            )
            if let collection = collections.firstObject {
                summaries.append(Self.summary(of: collection, kind: album.kind))
            }
        }
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        for index in 0..<userAlbums.count {
            summaries.append(Self.summary(of: userAlbums.object(at: index), kind: .user))
        }
        return summaries
    }

    /// The photos with these IDs that still exist, in `PhotoAsset.libraryOrder`. Fetched in batches of
    /// `idBatchSize`, each in its own `autoreleasepool`; burst members are included, hidden photos are not.
    public func assets(withIDs assetIDs: [String]) async -> [PhotoAsset] {
        var seen = Set<String>()
        let ids = assetIDs.filter { seen.insert($0).inserted }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %@", NSNumber(value: PHAssetMediaType.image.rawValue))
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = true
        var found: [PhotoAsset] = []
        var start = 0
        while start < ids.count {
            let batch = Array(ids[start..<min(start + Self.idBatchSize, ids.count)])
            autoreleasepool {
                let result = PHAsset.fetchAssets(withLocalIdentifiers: batch, options: options)
                result.enumerateObjects { asset, _, _ in
                    found.append(PhotoKitAssetMapper.asset(from: asset))
                }
            }
            start += Self.idBatchSize
        }
        return found.sorted(by: PhotoAsset.libraryOrder)
    }

    /// How many identifiers `assets(withIDs:)` passes to one `PHAsset.fetchAssets` call.
    static let idBatchSize = 500

    /// One fetch result per selected album, or one for the whole library.
    private static func fetchResults(for scope: ScanScope) -> [PHFetchResult<PHAsset>] {
        let options = PhotoKitFetchOptions.make(scope: scope)
        guard let albumIDs = scope.albumIDs else {
            return [PHAsset.fetchAssets(with: options)]
        }
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: albumIDs, options: nil)
        if collections.count < Set(albumIDs).count {
            let missing = Set(albumIDs).count - collections.count
            logger.info("Ignoring \(missing, privacy: .public) selected albums that no longer exist")
        }
        return (0..<collections.count).map { PHAsset.fetchAssets(in: collections.object(at: $0), options: options) }
    }

    /// The summary of `collection`, with PhotoKit's estimated count or, if it has none, the image count.
    private static func summary(of collection: PHAssetCollection, kind: AlbumKind) -> AlbumSummary {
        var count = collection.estimatedAssetCount
        if count == NSNotFound {
            // Smart albums often have no estimate; a lazy image-only fetch gives the count without loading assets.
            count = PHAsset.fetchAssets(in: collection, options: PhotoKitFetchOptions.make(scope: .allPhotos)).count
        }
        return AlbumSummary(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "",
            kind: kind,
            estimatedCount: count
        )
    }
}
