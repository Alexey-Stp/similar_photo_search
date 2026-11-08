import SwiftUI

/// Entry view of the app: builds the permission view model from the injected factory and shows `RootView`.
public struct RootHost: View {
    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: PermissionViewModel?

    /// Creates the host.
    public init() {}

    public var body: some View {
        Group {
            if let viewModel {
                RootView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil, let factory {
                viewModel = factory.makePermissionViewModel()
            }
        }
    }
}
