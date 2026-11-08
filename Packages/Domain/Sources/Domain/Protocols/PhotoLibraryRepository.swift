import Foundation

/// Read access to the user's photo library.
///
/// Authorization lives in `PhotoPermissionService`.
public protocol PhotoLibraryRepository: Sendable {
    /// Fetches all photos in the library as domain values.
    func fetchAssets() async throws -> [PhotoAsset]
}
