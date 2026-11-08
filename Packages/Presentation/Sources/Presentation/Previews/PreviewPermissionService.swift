#if DEBUG
import Domain

/// Fixed-state `PhotoPermissionService` for SwiftUI previews.
struct PreviewPermissionService: PhotoPermissionService {
    let status: PhotoLibraryAuthorization
    let photoCount: Int

    func currentStatus() async -> PhotoLibraryAuthorization { status }
    func requestAccess() async -> PhotoLibraryAuthorization { status }
    func accessiblePhotoCount() async -> Int { photoCount }
    func presentLimitedPicker() async {}
}

extension PermissionViewModel {
    /// A view model backed by `PreviewPermissionService`. Call `refresh()` to load the status.
    static func preview(status: PhotoLibraryAuthorization, photoCount: Int = 0) -> PermissionViewModel {
        PermissionViewModel(
            permissions: PreviewPermissionService(status: status, photoCount: photoCount),
            openSettings: {}
        )
    }
}
#endif
