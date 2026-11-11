import Domain
import Foundation
import os
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
    /// - Returns: The IDs the change block found and submitted for deletion. An ID that vanished after the caller's
    ///   check is not in the request, so this call did not delete it.
    /// - Throws: PhotoKit's error unchanged, including `PHPhotosError.userCancelled` when the user taps "Don't Allow".
    func deleteAssets(withIDs assetIDs: [String]) async throws -> Set<String>
}

/// `PhotoLibraryPerforming` over `PHPhotoLibrary.shared()`.
struct PhotoKitLibraryPerformer: PhotoLibraryPerforming {
    /// Maps `PHPhotoLibrary.authorizationStatus(for: .readWrite)` to the domain status.
    func readWriteAuthorization() -> PhotoLibraryAuthorization {
        PhotoKitPermissionService.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// Fetches `assetIDs` in one `autoreleasepool` and reads `canPerform(.delete)` for each asset found.
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

    /// Re-fetches `assetIDs` inside one change block and deletes what it finds; returns the IDs it submitted.
    func deleteAssets(withIDs assetIDs: [String]) async throws -> Set<String> {
        // The change block runs on an arbitrary queue: it captures only the identifiers and re-fetches inside.
        // The IDs it submits come back through a lock, never as `PHAsset`.
        let submitted = OSAllocatedUnfairLock(initialState: Set<String>())
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: Self.fetchOptions())
            // `withLock` takes a `@Sendable` closure, so it may only capture an immutable value.
            let found = Set((0..<assets.count).map { assets.object(at: $0).localIdentifier })
            submitted.withLock { $0 = found }
            PHAssetChangeRequest.deleteAssets(assets)
        }
        return submitted.withLock { $0 }
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
