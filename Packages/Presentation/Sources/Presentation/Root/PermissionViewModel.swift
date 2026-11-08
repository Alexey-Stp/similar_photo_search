import Domain
import Observation

/// Owns the photo library authorization state and decides which top-level screen is shown.
@Observable
@MainActor
public final class PermissionViewModel {
    /// The last known authorization status, or `nil` before the first `refresh()`.
    public private(set) var status: PhotoLibraryAuthorization?
    /// The number of photos shared with the app. Set only under limited access.
    public private(set) var accessiblePhotoCount: Int?

    /// The screen to show, or `nil` while the status is still unknown.
    public var route: AppRoute? {
        status.map(AppRoute.init(authorization:))
    }

    /// Whether the user shared only some of their photos.
    public var isLimited: Bool {
        status == .limited
    }

    private let permissions: any PhotoPermissionService
    private let openSettingsAction: @MainActor () -> Void

    /// Creates the view model.
    /// - Parameters:
    ///   - permissions: Reads and requests photo library access.
    ///   - openSettings: Opens the app's page in the Settings app.
    public init(
        permissions: any PhotoPermissionService,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.permissions = permissions
        self.openSettingsAction = openSettings
    }

    /// Re-reads the status without prompting. Call on launch and whenever the scene becomes active,
    /// so a change made in Settings shows up without restarting the app.
    public func refresh() async {
        await apply(await permissions.currentStatus())
    }

    /// Shows the system access prompt (if the user was not asked before) and applies the result.
    public func requestAccess() async {
        await apply(await permissions.requestAccess())
    }

    /// Lets the user change which photos are shared, then reloads the status and the photo count.
    public func presentLimitedPicker() async {
        await permissions.presentLimitedPicker()
        await refresh()
    }

    /// Opens the app's page in Settings.
    public func openSettings() {
        openSettingsAction()
    }

    private func apply(_ newStatus: PhotoLibraryAuthorization) async {
        // Load the count first, so status and count change together and the banner never shows a stale number.
        let count = newStatus == .limited ? await permissions.accessiblePhotoCount() : nil
        status = newStatus
        accessiblePhotoCount = count
    }
}
