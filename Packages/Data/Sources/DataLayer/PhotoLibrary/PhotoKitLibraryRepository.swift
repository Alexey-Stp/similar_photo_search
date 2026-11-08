import Domain
import Foundation

/// PhotoKit-backed photo library. Placeholder until the photo library ticket implements it.
public actor PhotoKitLibraryRepository: PhotoLibraryRepository {
    /// Creates the repository.
    public init() {}

    public func authorizationStatus() async -> PhotoLibraryAuthorization {
        fatalError("Not implemented")
    }

    public func requestAuthorization() async -> PhotoLibraryAuthorization {
        fatalError("Not implemented")
    }

    public func fetchAssets() async throws -> [PhotoAsset] {
        fatalError("Not implemented")
    }
}
