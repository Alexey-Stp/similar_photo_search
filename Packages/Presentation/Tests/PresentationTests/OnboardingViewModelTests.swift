import Domain
import DomainTestSupport
import Presentation
import Testing

@MainActor
struct OnboardingViewModelTests {
    private func makeViewModel(
        _ service: MockPhotoPermissionService,
        completions: CompletionCounter = CompletionCounter()
    ) async -> (OnboardingViewModel, PermissionViewModel) {
        let permission = PermissionViewModel(permissions: service, openSettings: {})
        await permission.refresh()
        let onboarding = OnboardingViewModel(permission: permission) { completions.count += 1 }
        return (onboarding, permission)
    }

    @Test func hasThreePages() async {
        let (viewModel, _) = await makeViewModel(MockPhotoPermissionService())
        #expect(viewModel.pages.count == 3)
        #expect(viewModel.pages.map(\.id) == [0, 1, 2])
    }

    @Test func newViewModelStartsOnFirstPage() async {
        // The page is kept only in memory, so a relaunch after a kill on page 2 starts over.
        let (viewModel, _) = await makeViewModel(MockPhotoPermissionService())
        #expect(viewModel.currentPage == 0)
        #expect(viewModel.isLastPage == false)
    }

    @Test func advanceMovesForwardAndStopsAtLastPage() async {
        let (viewModel, _) = await makeViewModel(MockPhotoPermissionService())
        viewModel.advance()
        #expect(viewModel.currentPage == 1)
        viewModel.advance()
        #expect(viewModel.currentPage == 2)
        #expect(viewModel.isLastPage)
        viewModel.advance()
        #expect(viewModel.currentPage == 2)
    }

    @Test func notDeterminedRequestsAccessThenCompletes() async {
        let service = MockPhotoPermissionService(status: .notDetermined, statusAfterRequest: .authorized)
        let completions = CompletionCounter()
        let (viewModel, permission) = await makeViewModel(service, completions: completions)
        #expect(viewModel.primaryAction == .allowAccess)

        await viewModel.performPrimaryAction()

        #expect(await service.requestAccessCallCount == 1)
        #expect(permission.status == .authorized)
        #expect(completions.count == 1)
        #expect(viewModel.isWorking == false)
    }

    @Test func deniedAfterPromptStillCompletes() async {
        let service = MockPhotoPermissionService(status: .notDetermined, statusAfterRequest: .denied)
        let completions = CompletionCounter()
        let (viewModel, permission) = await makeViewModel(service, completions: completions)

        await viewModel.performPrimaryAction()

        #expect(permission.route(hasCompletedOnboarding: true) == .permissionDenied)
        #expect(completions.count == 1)
    }

    @Test(arguments: [
        PhotoLibraryAuthorization.authorized, .limited, .denied, .restricted
    ])
    func alreadyDecidedContinuesWithoutPrompt(status: PhotoLibraryAuthorization) async {
        let service = MockPhotoPermissionService(status: status)
        let completions = CompletionCounter()
        let (viewModel, _) = await makeViewModel(service, completions: completions)
        #expect(viewModel.primaryAction == .continue)

        await viewModel.performPrimaryAction()

        #expect(await service.requestAccessCallCount == 0)
        #expect(completions.count == 1)
    }

    @Test func doubleTapRequestsAccessOnce() async {
        // Limited access makes the request wait on the photo count, which the mock can hold.
        let service = MockPhotoPermissionService(status: .notDetermined, statusAfterRequest: .limited)
        let completions = CompletionCounter()
        let (viewModel, _) = await makeViewModel(service, completions: completions)
        await service.holdNextPhotoCount()

        let firstTap = Task { await viewModel.performPrimaryAction() }
        while await !service.isHoldingPhotoCount {
            await Task.yield()
        }
        #expect(viewModel.isWorking)

        await viewModel.performPrimaryAction()
        #expect(await service.requestAccessCallCount == 1)
        #expect(completions.count == 0)

        await service.releaseHeldPhotoCount()
        await firstTap.value
        #expect(await service.requestAccessCallCount == 1)
        #expect(completions.count == 1)
        #expect(viewModel.isWorking == false)
    }
}

@MainActor
final class CompletionCounter {
    var count = 0
}
