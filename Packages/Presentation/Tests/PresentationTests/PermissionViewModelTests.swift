import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

@MainActor
struct PermissionViewModelTests {
    private func makeViewModel(
        _ service: MockPhotoPermissionService,
        library: MockPhotoLibraryRepository = MockPhotoLibraryRepository(),
        openSettings: @escaping @MainActor () -> Void = {}
    ) -> PermissionViewModel {
        PermissionViewModel(permissions: service, library: library, openSettings: openSettings)
    }

    /// A library of `count` photos; one of them is a screenshot, which the banner counts too.
    private func makeLibrary(photoCount count: Int) -> MockPhotoLibraryRepository {
        MockPhotoLibraryRepository(assets: photos(count))
    }

    private func photos(_ count: Int) -> [PhotoAsset] {
        (0..<count).map { index in
            PhotoAsset(
                id: "P\(index)",
                creationDate: Date(timeIntervalSince1970: TimeInterval(index)),
                pixelWidth: 100,
                pixelHeight: 100,
                isFavorite: false,
                mediaSubtypes: index == 0 ? [.screenshot] : []
            )
        }
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
        let library = MockPhotoLibraryRepository()
        let viewModel = makeViewModel(service, library: library)
        #expect(viewModel.route(hasCompletedOnboarding: true) == nil)
        #expect(await service.requestAccessCallCount == 0)
        #expect(await library.assetCountCallCount == 0)
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
        let service = MockPhotoPermissionService(status: .authorized)
        let viewModel = makeViewModel(service, library: makeLibrary(photoCount: 12))
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == nil)

        await service.setStatus(.limited)
        await viewModel.refresh()
        #expect(viewModel.isLimited)
        #expect(viewModel.accessiblePhotoCount == 12)
    }

    @Test func countIsLoadedOnlyUnderLimitedAccess() async {
        let service = MockPhotoPermissionService(status: .authorized)
        let library = makeLibrary(photoCount: 5)
        let viewModel = makeViewModel(service, library: library)
        await viewModel.refresh()
        #expect(await library.assetCountCallCount == 0)
        #expect(viewModel.accessiblePhotoCount == nil)
    }

    @Test func limitedToFullClearsCount() async {
        let service = MockPhotoPermissionService(status: .limited)
        let viewModel = makeViewModel(service, library: makeLibrary(photoCount: 5))
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == 5, "Screenshots are shared photos too")

        await service.setStatus(.authorized)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == nil)
        #expect(viewModel.isLimited == false)
    }

    @Test func olderLimitedRefreshDoesNotOverwriteNewerResult() async {
        let service = MockPhotoPermissionService(status: .limited)
        let library = makeLibrary(photoCount: 5)
        await library.holdNextAssetCount()
        let viewModel = makeViewModel(service, library: library)

        // The older refresh reads "limited" and then waits for its photo count.
        let olderRefresh = Task { await viewModel.refresh() }
        while await !library.isHoldingAssetCount {
            await Task.yield()
        }

        // A newer refresh finishes first, after access changed to full.
        await service.setStatus(.authorized)
        await viewModel.refresh()
        #expect(viewModel.status == .authorized)

        // The older result arrives late and must be ignored.
        await library.releaseHeldAssetCount()
        await olderRefresh.value
        #expect(viewModel.status == .authorized)
        #expect(viewModel.accessiblePhotoCount == nil)
        #expect(viewModel.isLimited == false)
    }

    @Test func olderLimitedRefreshDoesNotOverwriteNewerDenied() async {
        let service = MockPhotoPermissionService(status: .limited)
        let library = makeLibrary(photoCount: 5)
        await library.holdNextAssetCount()
        let viewModel = makeViewModel(service, library: library)

        let olderRefresh = Task { await viewModel.refresh() }
        while await !library.isHoldingAssetCount {
            await Task.yield()
        }

        await service.setStatus(.denied)
        await viewModel.refresh()

        await library.releaseHeldAssetCount()
        await olderRefresh.value
        #expect(viewModel.route(hasCompletedOnboarding: true) == .permissionDenied)
        #expect(viewModel.accessiblePhotoCount == nil)
    }

    @Test func presentLimitedPickerRefreshesCount() async {
        let service = MockPhotoPermissionService(status: .limited)
        let library = makeLibrary(photoCount: 3)
        let viewModel = makeViewModel(service, library: library)
        await viewModel.refresh()
        #expect(viewModel.accessiblePhotoCount == 3)

        // The user shares more photos in the picker.
        await library.setAssets(photos(30))
        await viewModel.presentLimitedPicker()
        #expect(await service.presentLimitedPickerCallCount == 1)
        #expect(viewModel.accessiblePhotoCount == 30)
    }

    @Test func openSettingsInvokesInjectedAction() {
        let counter = CallCounter()
        let viewModel = makeViewModel(MockPhotoPermissionService(status: .denied), openSettings: { counter.count += 1 })
        viewModel.openSettings()
        #expect(counter.count == 1)
    }
}

@MainActor
private final class CallCounter {
    var count = 0
}
