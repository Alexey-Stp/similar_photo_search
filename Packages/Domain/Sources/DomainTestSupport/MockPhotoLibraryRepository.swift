import Domain
import Foundation

/// In-memory `PhotoLibraryRepository` for tests.
public actor MockPhotoLibraryRepository: PhotoLibraryRepository {
    /// Assets returned by `fetchAssets()`.
    public let assets: [PhotoAsset]
    /// Error thrown by `fetchAssets()`, if set.
    public let fetchError: (any Error)?

    /// Creates the mock.
    public init(assets: [PhotoAsset] = [], fetchError: (any Error)? = nil) {
        self.assets = assets
        self.fetchError = fetchError
    }

    public func fetchAssets() throws -> [PhotoAsset] {
        if let fetchError {
            throw fetchError
        }
        return assets
    }
}
