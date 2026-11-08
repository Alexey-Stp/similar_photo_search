import SwiftUI

/// Switches between the top-level screens based on `PermissionViewModel.route`.
///
/// Re-reads the authorization status on launch and every time the scene becomes active,
/// so a change made in Settings is picked up without restarting the app.
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let viewModel: PermissionViewModel

    /// Creates the root view.
    public init(viewModel: PermissionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.route {
            case nil:
                ProgressView()
            case .onboarding:
                OnboardingView(viewModel: viewModel)
            case .permissionDenied:
                PermissionDeniedView(viewModel: viewModel)
            case .restricted:
                RestrictedAccessView()
            case .home:
                HomeView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.refresh() }
            }
        }
    }
}
