import Domain
import Observation

/// Decides which top-level screen is shown.
@Observable
@MainActor
public final class RootViewModel {
    /// The screen currently shown.
    public private(set) var route: AppRoute

    private let photoLibrary: any PhotoLibraryRepository

    /// Creates the view model.
    /// - Parameters:
    ///   - photoLibrary: Source of the photo library authorization status.
    ///   - initialRoute: Route shown before the status is known.
    public init(photoLibrary: any PhotoLibraryRepository, initialRoute: AppRoute = .onboarding) {
        self.photoLibrary = photoLibrary
        self.route = initialRoute
    }

    /// Re-reads the authorization status without prompting and updates `route`.
    public func refreshRoute() async {
        route = AppRoute(authorization: await photoLibrary.authorizationStatus())
    }

    /// Asks the user for photo access and updates `route` with the result.
    public func requestAccess() async {
        route = AppRoute(authorization: await photoLibrary.requestAuthorization())
    }
}
