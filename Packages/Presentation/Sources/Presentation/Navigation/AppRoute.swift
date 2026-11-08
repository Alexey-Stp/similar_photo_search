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

    /// The route for a photo library authorization status.
    public init(authorization: PhotoLibraryAuthorization) {
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
