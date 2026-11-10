import Domain
import Observation

/// Owns the photo library authorization state and decides which top-level screen is shown.
@Observable
@MainActor
public final class PermissionViewModel {
    /// The last known authorization status, or `nil` before the first `refresh()`.
    public private(set) var status: PhotoLibraryAuthorization?
    /// The number of photos shared with the app (`PhotoLibraryRepository.assetCount`, screenshots included). Set
    /// only under limited access.
    public private(set) var accessiblePhotoCount: Int?

    /// The screen to show, or `nil` while the status is still unknown.
    /// - Parameter hasCompletedOnboarding: Whether the user finished the welcome flow.
    public func route(hasCompletedOnboarding: Bool) -> AppRoute? {
        status.map { AppRoute(authorization: $0, hasCompletedOnboarding: hasCompletedOnboarding) }
    }

    /// Whether the user shared only some of their photos.
    public var isLimited: Bool {
        status == .limited
    }

    private let permissions: any PhotoPermissionService
    private let library: any PhotoLibraryRepository
    private let openSettingsAction: @MainActor () -> Void
    /// Incremented by every refresh or request, so a slower, older one cannot overwrite a newer result.
    private var latestRequestID = 0

    /// Creates the view model.
    /// - Parameters:
    ///   - permissions: Reads and requests photo library access.
    ///   - library: Counts the photos shared with the app for the limited-access banner.
    ///   - openSettings: Opens the app's page in the Settings app.
    public init(
        permissions: any PhotoPermissionService,
        library: any PhotoLibraryRepository,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.permissions = permissions
        self.library = library
        self.openSettingsAction = openSettings
    }

    /// Re-reads the status without prompting. Call on launch and whenever the scene becomes active,
    /// so a change made in Settings shows up without restarting the app.
    public func refresh() async {
        let requestID = beginRequest()
        await apply(await permissions.currentStatus(), requestID: requestID)
    }

    /// Shows the system access prompt (if the user was not asked before) and applies the result.
    public func requestAccess() async {
        let requestID = beginRequest()
        await apply(await permissions.requestAccess(), requestID: requestID)
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

    /// Every photo the app can see, screenshots included: what the banner calls "shared".
    static let sharedPhotosScope = ScanScope(excludeScreenshots: false)

    private func beginRequest() -> Int {
        latestRequestID += 1
        return latestRequestID
    }

    private func apply(_ newStatus: PhotoLibraryAuthorization, requestID: Int) async {
        // Load the count first, so status and count change together and the banner never shows a stale number.
        let count = newStatus == .limited ? await library.assetCount(scope: Self.sharedPhotosScope) : nil
        // A newer refresh or request started while this one was waiting: keep its status and count.
        guard requestID == latestRequestID else { return }
        status = newStatus
        accessiblePhotoCount = count
    }
}
