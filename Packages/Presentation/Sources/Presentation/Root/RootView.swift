import SwiftUI

/// Switches between the top-level screens based on `RootViewModel.route`.
public struct RootView: View {
    private let viewModel: RootViewModel

    /// Creates the root view.
    public init(viewModel: RootViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        switch viewModel.route {
        case .onboarding:
            OnboardingView(viewModel: viewModel)
        case .permissionDenied:
            PermissionDeniedView()
        case .home:
            HomeView()
        }
    }
}
