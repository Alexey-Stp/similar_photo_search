import Domain
import Foundation

/// Deletes assets through one `PHPhotoLibrary.performChanges` call. Placeholder until the deletion ticket.
public actor PhotoKitAssetDeletionService: AssetDeletionService {
    /// Creates the service.
    public init() {}

    public func delete(assetIDs: [String]) async throws -> DeletionOutcome {
        fatalError("Not implemented")
    }
}
