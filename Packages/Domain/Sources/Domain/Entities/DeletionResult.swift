import Foundation

/// Why one photo was not deleted.
public enum DeletionError: Error, Sendable, Hashable {
    /// The photo is gone or no longer accessible: deleted elsewhere, or removed from Limited access.
    case unavailable
    /// The library does not allow deleting this photo, for example one in a shared album.
    case notDeletable
    /// The app does not have read-write access to the library, for example because it was revoked mid-session.
    case permissionDenied
    /// The system reported success, but the photo is still in the library.
    case notDeleted
    /// Any other failure. The message is diagnostic (error domain and code), not meant for the user.
    case unknown(String)
}

/// Result of asking the system to delete photos.
///
/// A user cancel is a normal outcome, not an error: `cancelled` is `true`, `deleted` is empty and no photo changed.
/// `failed` then holds only what was known before the system alert (`unavailable`, `notDeletable`).
public struct DeletionResult: Sendable, Hashable {
    /// IDs this call deleted, confirmed by re-fetching them afterwards.
    public var deleted: Set<String>
    /// IDs that were not deleted, with the reason.
    public var failed: [String: DeletionError]
    /// The user dismissed the system confirmation ("Don't Allow").
    public var cancelled: Bool

    /// Creates a result.
    public init(deleted: Set<String> = [], failed: [String: DeletionError] = [:], cancelled: Bool = false) {
        self.deleted = deleted
        self.failed = failed
        self.cancelled = cancelled
    }

    /// Every one of `assetIDs` failed with `.permissionDenied`.
    public static func permissionDenied(for assetIDs: some Sequence<String>) -> DeletionResult {
        DeletionResult(failed: Dictionary(assetIDs.map { ($0, .permissionDenied) }) { first, _ in first })
    }

    /// `true` when the call failed because the app lacks read-write access.
    public var isPermissionDenied: Bool {
        failed.values.contains(.permissionDenied)
    }
}
