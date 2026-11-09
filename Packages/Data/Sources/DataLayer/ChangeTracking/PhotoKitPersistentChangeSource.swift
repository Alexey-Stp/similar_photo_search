import Domain
import Foundation
import Photos

/// `PersistentChangeSource` over `PHPhotoLibrary.shared()`.
struct PhotoKitPersistentChangeSource: PersistentChangeSource {
    /// Asset IDs read per `autoreleasepool` while listing the library.
    static let listingBatchSize = 1_000

    func currentToken() -> Data? {
        try? NSKeyedArchiver.archivedData(
            withRootObject: PHPhotoLibrary.shared().currentChangeToken,
            requiringSecureCoding: true
        )
    }

    func assetChanges(since token: Data) throws -> LibraryDelta {
        let decoded: PHPersistentChangeToken?
        do {
            decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: token)
        } catch {
            throw PersistentChangeError.unreadableToken
        }
        guard let decoded else { throw PersistentChangeError.unreadableToken }

        let changes: PHPersistentChangeFetchResult
        do {
            changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: decoded)
        } catch {
            throw Self.map(error)
        }

        var delta = LibraryDelta()
        for change in changes {
            try Task.checkCancellation()
            try autoreleasepool {
                let details: PHPersistentObjectChangeDetails
                do {
                    details = try change.changeDetails(for: .asset)
                } catch {
                    throw Self.map(error)
                }
                delta.record(
                    inserted: details.insertedLocalIdentifiers,
                    updated: details.updatedLocalIdentifiers,
                    deleted: details.deletedLocalIdentifiers
                )
            }
        }
        return delta
    }

    func allAssetIDs() throws -> Set<String> {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        // Burst members can be analysed (scope `includeBursts`), so they must not look deleted to the full diff.
        options.includeAllBurstAssets = true
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var ids = Set<String>(minimumCapacity: assets.count)
        var start = 0
        while start < assets.count {
            try Task.checkCancellation()
            let end = min(start + Self.listingBatchSize, assets.count)
            autoreleasepool {
                for index in start..<end {
                    ids.insert(assets.object(at: index).localIdentifier)
                }
            }
            start = end
        }
        return ids
    }

    /// Maps a PhotoKit error from the change history to the fallback it causes.
    static func map(_ error: any Error) -> PersistentChangeError {
        let error = error as NSError
        guard error.domain == PHPhotosErrorDomain else { return .other }
        switch error.code {
        case PHPhotosError.Code.persistentChangeTokenExpired.rawValue:
            return .tokenExpired
        case PHPhotosError.Code.persistentChangeDetailsUnavailable.rawValue:
            return .detailsUnavailable
        default:
            return .other
        }
    }
}
