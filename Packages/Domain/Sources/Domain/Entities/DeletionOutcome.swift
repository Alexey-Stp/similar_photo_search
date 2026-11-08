import Foundation

/// Result of asking the system to delete photos.
public enum DeletionOutcome: Sendable, Hashable {
    /// The photos were deleted.
    case deleted
    /// The user cancelled the system confirmation. This is a normal outcome, not an error.
    case cancelledByUser
}
