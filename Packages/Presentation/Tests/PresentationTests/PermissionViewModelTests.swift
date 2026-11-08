import Domain
import DomainTestSupport
import Presentation
import Testing

@MainActor
struct PermissionViewModelTests {
    private func makeViewModel(
        _ service: MockPhotoPermissionService,
        openSettings: @escaping @MainActor () -> Void = {}
    ) -> PermissionViewModel {
        PermissionViewModel(permissions: service, openSettings: openSettings)
    }

    @Test(arguments: [
        (PhotoLibraryAuthorization.notDetermined, AppRoute.onboarding),
        (.authorized, .home),
        (.limited, .home),
        (.denied, .permissionDenied),
        (.restricted, .restricted)
    ])
    func refreshMapsEveryStatusToRoute(status: PhotoLibraryAuthorization, expected: AppRoute) async {
        let viewModel = makeViewModel(MockPhotoPermissionService(status: status))
        await viewModel.refresh()
        #expect(viewModel.status == status)
        #expect(viewModel.route(hasCompletedOnboarding: true) == expected)
    }

    @Test(arguments: [
        PhotoLibraryAuthorization.notDetermined, .authorized, .limited, .denied, .restricted
    ])
    func unfinishedOnboardingAlwaysRoutesToOnboarding(status: PhotoLibraryAuthorization) async {
        let viewModel = makeViewModel(MockPhotoPermissionService(status: status))
        await viewModel.refresh()
        #expect(viewModel.route(hasCompletedOnboarding: false) == .onboarding)
    }

    @Test func startsWithUnknownRouteWithoutTouchingTheLibrary() async {
        let service = MockPhotoPermissionService(status: .authorized)
        let viewModel = makeViewModel(service)
        #expect(viewModel.route(hasCompletedOnboarding: true) == nil)
        #expect(await service.requestAccessCallCount == 0)
        #expect(await service.photoCountCallCount == 0)
    }

    @Test(arguments: [
        PhotoLibraryAuthorization.authorized, .limited, .denied, .restricted
    ])
    func requestAccessPromptsOnceAndRoutesToResult(result: PhotoLibraryAuthorization) async {
        let service = MockPhotoPermissionService(status: .notDetermined, statusAfterRequest: result)
        let viewModel = makeViewModel(service)
        await viewModel.requestAccess()
        let expected = AppRoute(authorization: result, hasCompletedOnboarding: true)
        #expect(viewModel.route(hasCompletedOnboarding: true) == expected)
        #expect(await service.requestAccessCallCount == 1)
    }

    @Test func refreshPicksUpChangeMadeInSettings() async {
        let service = MockPhotoPermissionService(status: .denied)
        let viewModel = makeViewModel(service)
        await viewModel.refresh()
        #expect(viewModel.route(hasCompletedOnboarding: true) == .permissionDenied)

        await service.setStatus(.authorized)
        await viewModel.refresh()
        #expect(viewModel.route(hasCompletedOnboarding: true) == .home)
        #expect(viewModel.isLimited == false)
    }

    @Test func refreshFromFullToLimitedLoadsCount() async {
        let service = MockPhotoPermissionService(status: .authorized, photoCount: 12)
        let viewModel = makeViewModel(service)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == nil)

        await service.setStatus(.limited)
        await viewModel.refresh()
        #expect(viewModel.isLimited)
        #expect(viewModel.accessiblePhotoCount == 12)
    }

    @Test func countIsLoadedOnlyUnderLimitedAccess() async {
        let service = MockPhotoPermissionService(status: .authorized, photoCount: 5)
        let viewModel = makeViewModel(service)
        await viewModel.refresh()
        #expect(await service.photoCountCallCount == 0)
        #expect(viewModel.accessiblePhotoCount == nil)
    }

    @Test func limitedToFullClearsCount() async {
        let service = MockPhotoPermissionService(status: .limited, photoCount: 5)
        let viewModel = makeViewModel(service)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == 5)

        await service.setStatus(.authorized)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == nil)
        #expect(viewModel.isLimited == false)
    }

    @Test func olderLimitedRefreshDoesNotOverwriteNewerResult() async {
        let service = MockPhotoPermissionService(status: .limited, photoCount: 5)
        await service.holdNextPhotoCount()
        let viewModel = makeViewModel(service)

        // The older refresh reads "limited" and then waits for its photo count.
        let olderRefresh = Task { await viewModel.refresh() }
        while await !service.isHoldingPhotoCount {
            await Task.yield()
        }

        // A newer refresh finishes first, after access changed to full.
        await service.setStatus(.authorized)
        await viewModel.refresh()
        #expect(viewModel.status == .authorized)

        // The older result arrives late and must be ignored.
        await service.releaseHeldPhotoCount()
        await olderRefresh.value
        #expect(viewModel.status == .authorized)
        #expect(viewModel.accessiblePhotoCount == nil)
        #expect(viewModel.isLimited == false)
    }

    @Test func olderLimitedRefreshDoesNotOverwriteNewerDenied() async {
        let service = MockPhotoPermissionService(status: .limited, photoCount: 5)
        await service.holdNextPhotoCount()
        let viewModel = makeViewModel(service)

        let olderRefresh = Task { await viewModel.refresh() }
        while await !service.isHoldingPhotoCount {
            await Task.yield()
        }

        await service.setStatus(.denied)
        await viewModel.refresh()

        await service.releaseHeldPhotoCount()
        await olderRefresh.value
        #expect(viewModel.route(hasCompletedOnboarding: true) == .permissionDenied)
        #expect(viewModel.accessiblePhotoCount == nil)
    }

    @Test func presentLimitedPickerRefreshesCount() async {
        let service = MockPhotoPermissionService(status: .limited, photoCount: 3, photoCountAfterPicker: 30)
        let viewModel = makeViewModel(service)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == 3)

        await viewModel.presentLimitedPicker()
        #expect(await service.presentLimitedPickerCallCount == 1)
        #expect(viewModel.accessiblePhotoCount == 30)
    }

    @Test func openSettingsInvokesInjectedAction() {
        let counter = CallCounter()
        let viewModel = makeViewModel(MockPhotoPermissionService(status: .denied)) { counter.count += 1 }
        viewModel.openSettings()
        #expect(counter.count == 1)
    }
}

@MainActor
private final class CallCounter {
    var count = 0
}
