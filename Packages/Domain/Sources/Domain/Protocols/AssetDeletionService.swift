import Foundation

/// Deletes photos from the library after an explicit user action.
public protocol AssetDeletionService: Sendable {
    /// Deletes the photos in one system request; the system shows its own confirmation alert.
    ///
    /// Every outcome is typed, so the call does not throw: a user cancel sets `cancelled`, missing access fails every
    /// ID with `.permissionDenied`, and each photo that was not deleted is in `failed` with its reason. An empty
    /// `assetIDs` returns an empty result without showing an alert.
    func delete(assetIDs: [String]) async -> DeletionResult
}
