import Domain

/// Top-level screens of the app.
public enum AppRoute: Sendable, Equatable {
    /// First launch: explain the app and ask for photo access.
    case onboarding
    /// The user denied photo access; they can turn it on in Settings.
    case permissionDenied
    /// Photo access is blocked by parental controls or device management; the user cannot change it.
    case restricted
    /// Main screen. Also used for limited access, together with a banner.
    case home

    /// The route for a photo library authorization status and onboarding progress.
    ///
    /// Onboarding is shown until the user finishes it, whatever the status (for example after a
    /// reinstall with access already granted), and again whenever the status is `.notDetermined`.
    /// - Parameters:
    ///   - authorization: The current photo library authorization status.
    ///   - hasCompletedOnboarding: Whether the user finished the welcome flow.
    public init(authorization: PhotoLibraryAuthorization, hasCompletedOnboarding: Bool) {
        guard hasCompletedOnboarding else {
            self = .onboarding
            return
        }
        switch authorization {
        case .notDetermined:
            self = .onboarding
        case .authorized, .limited:
            self = .home
        case .denied:
            self = .permissionDenied
        case .restricted:
            self = .restricted
        }
    }
}
