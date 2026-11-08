import Foundation

/// The app's access level to the photo library, independent of PhotoKit.
public enum PhotoLibraryAuthorization: Sendable, Hashable, CaseIterable {
    /// The user has not been asked yet.
    case notDetermined
    /// Full read-write access.
    case authorized
    /// Access to a user-selected subset of photos.
    case limited
    /// The user denied access.
    case denied
    /// Access is restricted, for example by parental controls.
    case restricted
}
