import SwiftUI

/// The deletion flow presented over the group list: review, progress until the system alert is answered, result.
///
/// Builds its view model once per presentation through the app's `ViewModelFactory`. It can't be swiped away
/// while the deletion runs.
struct DeletionSheet: View {
    let request: ClusterListViewModel.DeletionRequest
    /// Closes the sheet (Cancel on the review, Done on the result).
    let onClose: () -> Void

    @Environment(\.viewModelFactory) private var factory
    @State private var viewModel: DeletionViewModel?

    /// The current step once the view model exists.
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    DeletionFlowView(viewModel: viewModel, onClose: onClose)
                } else {
                    ProgressView()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .interactiveDismissDisabled(viewModel?.isDismissDisabled ?? false)
        .onAppear {
            if viewModel == nil {
                viewModel = factory?.makeDeletionViewModel(request: request)
            }
        }
    }
}

/// Switches between the steps of the flow.
struct DeletionFlowView: View {
    let viewModel: DeletionViewModel
    let onClose: () -> Void

    /// The view of the current state.
    var body: some View {
        switch viewModel.state {
        case .review:
            DeletionReviewView(viewModel: viewModel, onCancel: onClose)
        case .deleting:
            DeletionProgressView()
        case .success(let outcome):
            DeletionResultView(outcome: outcome, isPartial: false, viewModel: viewModel, onDone: onClose)
        case .partial(let outcome):
            DeletionResultView(outcome: outcome, isPartial: true, viewModel: viewModel, onDone: onClose)
        case .failed(let message):
            DeletionFailedView(message: message, onDone: onClose)
        }
    }
}

/// "Deleting…" while the system alert is up and the deletion runs. No way to dismiss it.
struct DeletionProgressView: View {
    /// A spinner with an explanation.
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("deletion.progress.title", bundle: .module)
                .font(.headline)
            Text("deletion.progress.message", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .navigationTitle(Text("deletion.progress.title", bundle: .module))
    }
}

/// Nothing could be deleted (for example access to the library was revoked).
struct DeletionFailedView: View {
    let message: String
    let onDone: () -> Void

    /// The message and a Done button.
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("deletion.error.title", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(message)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onDone) {
                    Text("deletion.done", bundle: .module)
                }
            }
        }
    }
}
