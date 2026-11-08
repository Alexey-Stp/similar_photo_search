import Domain

/// Top-level screens of the app.
public enum AppRoute: Sendable, Equatable {
    /// First launch: explain the app and ask for photo access.
    case onboarding
    /// Photo access was denied or is restricted.
    case permissionDenied
    /// Main screen.
    case home

    /// The route for a photo library authorization status.
    public init(authorization: PhotoLibraryAuthorization) {
        switch authorization {
        case .notDetermined:
            self = .onboarding
        case .authorized, .limited:
            self = .home
        case .denied, .restricted:
            self = .permissionDenied
        }
    }
}
