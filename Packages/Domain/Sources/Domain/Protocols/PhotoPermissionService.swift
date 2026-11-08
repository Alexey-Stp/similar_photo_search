import Foundation

/// Reads and requests read-write access to the user's photo library.
public protocol PhotoPermissionService: Sendable {
    /// The current authorization status. Never shows a system prompt.
    func currentStatus() async -> PhotoLibraryAuthorization

    /// Shows the system prompt for read-write access if the status is not determined yet,
    /// and returns the resulting status.
    func requestAccess() async -> PhotoLibraryAuthorization

    /// The number of photos the app can see. Under limited access this is the user's selection.
    func accessiblePhotoCount() async -> Int

    /// Shows the system picker that changes the limited-access selection.
    /// Returns when the picker is dismissed, or immediately if it cannot be shown.
    func presentLimitedPicker() async
}
