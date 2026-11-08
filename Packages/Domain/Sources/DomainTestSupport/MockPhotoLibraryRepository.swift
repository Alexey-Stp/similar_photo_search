import Domain
import Foundation

/// In-memory `PhotoLibraryRepository` for tests.
public actor MockPhotoLibraryRepository: PhotoLibraryRepository {
    /// Status returned by `authorizationStatus()`.
    public private(set) var status: PhotoLibraryAuthorization
    /// Status the mock switches to when `requestAuthorization()` is called.
    public let statusAfterRequest: PhotoLibraryAuthorization
    /// Assets returned by `fetchAssets()`.
    public let assets: [PhotoAsset]
    /// Error thrown by `fetchAssets()`, if set.
    public let fetchError: (any Error)?
    /// Number of `requestAuthorization()` calls.
    public private(set) var requestAuthorizationCallCount = 0

    /// Creates the mock.
    public init(
        status: PhotoLibraryAuthorization = .notDetermined,
        statusAfterRequest: PhotoLibraryAuthorization = .authorized,
        assets: [PhotoAsset] = [],
        fetchError: (any Error)? = nil
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
        self.assets = assets
        self.fetchError = fetchError
    }

    public func authorizationStatus() -> PhotoLibraryAuthorization {
        status
    }

    public func requestAuthorization() -> PhotoLibraryAuthorization {
        requestAuthorizationCallCount += 1
        status = statusAfterRequest
        return status
    }

    public func fetchAssets() throws -> [PhotoAsset] {
        if let fetchError {
            throw fetchError
        }
        return assets
    }
}
