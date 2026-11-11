@testable import DataLayer
import Domain
import Foundation
import Photos

/// A scripted photo library for `PhotoKitAssetDeletionService` tests.
final class FakePhotoLibraryPerformer: PhotoLibraryPerforming, @unchecked Sendable {
    // @unchecked: each test drives it from one task at a time.

    /// The access level reported to the service.
    var authorization: PhotoLibraryAuthorization = .authorized
    /// Assets in the library: ID → whether it allows `.delete`.
    var assets: [String: Bool]
    /// Errors thrown by successive delete requests; `nil` or an exhausted script means success.
    var responses: [(any Error)?] = []
    /// Whether a successful request removes the assets. `false` simulates "success, but still there".
    var removesAssetsOnSuccess = true
    /// IDs deleted elsewhere between the service's check and the change block.
    var vanishBeforeRequest: Set<String> = []
    /// IDs passed to each delete request, in order.
    private(set) var deleteRequests: [[String]] = []

    /// Creates a library of `deletable` assets plus `notDeletable` ones.
    init(deletable: [String] = [], notDeletable: [String] = []) {
        var assets: [String: Bool] = [:]
        deletable.forEach { assets[$0] = true }
        notDeletable.forEach { assets[$0] = false }
        self.assets = assets
    }

    /// Returns `authorization`.
    func readWriteAuthorization() -> PhotoLibraryAuthorization {
        authorization
    }

    /// The entries of `assets` for the requested IDs.
    func deletability(of assetIDs: [String]) -> [String: Bool] {
        assets.filter { assetIDs.contains($0.key) }
    }

    /// Records the request, removes `vanishBeforeRequest` from the library (deleted elsewhere after the check), then
    /// throws the next scripted error or returns the requested IDs still in the library.
    func deleteAssets(withIDs assetIDs: [String]) async throws -> Set<String> {
        deleteRequests.append(assetIDs)
        vanishBeforeRequest.forEach { assets[$0] = nil }
        if !responses.isEmpty, let error = responses.removeFirst() {
            throw error
        }
        let submitted = Set(assetIDs.filter { assets[$0] != nil })
        if removesAssetsOnSuccess {
            submitted.forEach { assets[$0] = nil }
        }
        return submitted
    }

    /// The error PhotoKit reports for `code`.
    static func photosError(_ code: PHPhotosError.Code) -> NSError {
        NSError(domain: PHPhotosErrorDomain, code: code.rawValue)
    }
}
