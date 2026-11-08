import Domain
import Presentation
import Testing

struct AppRouteTests {
    @Test(arguments: [
        (PhotoLibraryAuthorization.notDetermined, AppRoute.onboarding),
        (.authorized, .home),
        (.limited, .home),
        (.denied, .permissionDenied),
        (.restricted, .restricted)
    ])
    func completedOnboardingRoutesByStatus(status: PhotoLibraryAuthorization, expected: AppRoute) {
        #expect(AppRoute(authorization: status, hasCompletedOnboarding: true) == expected)
    }

    @Test(arguments: [
        PhotoLibraryAuthorization.notDetermined, .authorized, .limited, .denied, .restricted
    ])
    func unfinishedOnboardingAlwaysShowsOnboarding(status: PhotoLibraryAuthorization) {
        #expect(AppRoute(authorization: status, hasCompletedOnboarding: false) == .onboarding)
    }

    @Test func restrictedIsNotTheDeniedScreen() {
        #expect(
            AppRoute(authorization: .restricted, hasCompletedOnboarding: true)
                != AppRoute(authorization: .denied, hasCompletedOnboarding: true)
        )
    }
}
