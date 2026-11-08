import Domain
import DomainTestSupport
import Presentation
import Testing

@MainActor
struct RootViewModelTests {
    @Test(arguments: [
        (PhotoLibraryAuthorization.notDetermined, AppRoute.onboarding),
        (.authorized, .home),
        (.limited, .home),
        (.denied, .permissionDenied),
        (.restricted, .permissionDenied)
    ])
    func refreshRouteMapsAuthorizationToRoute(status: PhotoLibraryAuthorization, expected: AppRoute) async {
        let viewModel = RootViewModel(photoLibrary: MockPhotoLibraryRepository(status: status))
        await viewModel.refreshRoute()
        #expect(viewModel.route == expected)
    }

    @Test func startsOnOnboardingWithoutTouchingTheLibrary() async {
        let library = MockPhotoLibraryRepository(status: .authorized)
        let viewModel = RootViewModel(photoLibrary: library)
        #expect(viewModel.route == .onboarding)
        #expect(await library.requestAuthorizationCallCount == 0)
    }

    @Test func requestAccessPromptsOnceAndRoutesToResult() async {
        let library = MockPhotoLibraryRepository(status: .notDetermined, statusAfterRequest: .denied)
        let viewModel = RootViewModel(photoLibrary: library)
        await viewModel.requestAccess()
        #expect(viewModel.route == .permissionDenied)
        #expect(await library.requestAuthorizationCallCount == 1)
    }
}
