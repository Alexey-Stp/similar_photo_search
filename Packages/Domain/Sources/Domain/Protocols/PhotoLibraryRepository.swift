import Foundation

/// Read access to the user's photo library.
public protocol PhotoLibraryRepository: Sendable {
    /// The current authorization status, without prompting the user.
    func authorizationStatus() async -> PhotoLibraryAuthorization

    /// Prompts the user for read-write access if needed and returns the resulting status.
    func requestAuthorization() async -> PhotoLibraryAuthorization

    /// Fetches all photos in the library as domain values.
    func fetchAssets() async throws -> [PhotoAsset]
}
