import Domain
import Foundation
import Photos

/// The PhotoKit calls `PhotoKitAssetDeletionService` needs. Only identifiers cross this boundary, never `PHAsset`, so
/// the service and its tests stay free of PhotoKit objects.
protocol PhotoLibraryPerforming: Sendable {
    /// The `.readWrite` access level, without prompting.
    func readWriteAuthorization() -> PhotoLibraryAuthorization

    /// Re-fetches `assetIDs`. For each asset found, whether it allows `.delete`; IDs that are gone or not accessible
    /// (for example outside Limited access) are absent.
    func deletability(of assetIDs: [String]) -> [String: Bool]

    /// Deletes `assetIDs` in one `PHPhotoLibrary.performChanges` call, which shows one system alert.
    ///
    /// Throws PhotoKit's error unchanged, including `PHPhotosError.userCancelled` when the user taps "Don't Allow".
    func deleteAssets(withIDs assetIDs: [String]) async throws
}

/// `PhotoLibraryPerforming` over `PHPhotoLibrary.shared()`.
struct PhotoKitLibraryPerformer: PhotoLibraryPerforming {
    func readWriteAuthorization() -> PhotoLibraryAuthorization {
        PhotoKitPermissionService.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func deletability(of assetIDs: [String]) -> [String: Bool] {
        guard !assetIDs.isEmpty else { return [:] }
        return autoreleasepool {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: Self.fetchOptions())
            var deletability = [String: Bool](minimumCapacity: assets.count)
            for index in 0..<assets.count {
                let asset = assets.object(at: index)
                deletability[asset.localIdentifier] = asset.canPerform(.delete)
            }
            return deletability
        }
    }

    func deleteAssets(withIDs assetIDs: [String]) async throws {
        // The change block runs on an arbitrary queue: it captures only the identifiers and re-fetches inside.
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: Self.fetchOptions())
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    /// Finds every requested asset that still exists, including burst members and hidden photos, so a photo that
    /// survived a deletion is never mistaken for a deleted one.
    private static func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = true
        return options
    }
}
