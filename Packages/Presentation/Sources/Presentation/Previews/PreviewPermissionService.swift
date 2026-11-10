#if DEBUG
import Domain

/// Fixed-state `PhotoPermissionService` for SwiftUI previews.
struct PreviewPermissionService: PhotoPermissionService {
    let status: PhotoLibraryAuthorization

    /// Returns the fixed status.
    func currentStatus() async -> PhotoLibraryAuthorization { status }
    /// Returns the fixed status; previews never prompt.
    func requestAccess() async -> PhotoLibraryAuthorization { status }
    /// Does nothing; previews can't show the system picker.
    func presentLimitedPicker() async {}
}

extension PermissionViewModel {
    /// A view model backed by `PreviewPermissionService`; the library holds `photoCount` photos. Call `refresh()` to
    /// load the status.
    static func preview(status: PhotoLibraryAuthorization, photoCount: Int = 0) -> PermissionViewModel {
        PermissionViewModel(
            permissions: PreviewPermissionService(status: status),
            library: PreviewPhotoLibraryRepository(albumList: [], libraryCount: photoCount),
            openSettings: {}
        )
    }
}
#endif
