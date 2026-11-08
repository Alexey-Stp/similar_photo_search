import Foundation

/// Deletes photos from the library after an explicit user action.
public protocol AssetDeletionService: Sendable {
    /// Deletes the photos in one system request.
    ///
    /// - Returns: `.cancelledByUser` when the user dismisses the system confirmation.
    func delete(assetIDs: [String]) async throws -> DeletionOutcome
}
