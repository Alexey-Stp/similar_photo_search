import SwiftUI

/// The card of one group as a row of a list (the group list, the groups on Home); appearing moves the prefetch
/// window.
struct ClusterCardRow: View {
    let viewModel: ClusterListViewModel
    let clusterID: String
    let onCompare: (String) -> Void

    var body: some View {
        if let card = viewModel.card(for: clusterID), let state = viewModel.selection.state(for: clusterID) {
            ClusterCardView(
                card: card,
                state: state,
                pixelSize: viewModel.pixelSize,
                thumbnails: viewModel.thumbnails,
                onToggle: { viewModel.toggle($0, in: clusterID) },
                onCompare: { onCompare(clusterID) }
            )
            .equatable()
            .onAppear { viewModel.rowAppeared(clusterID) }
        }
    }
}

extension View {
    /// "Delete every photo of this group?" while a group waits for it (selecting its last kept photo).
    /// - Parameter isActive: Whether this screen asks; only the screen on top should, so the dialog shows once.
    func deleteAllConfirmation(_ viewModel: ClusterListViewModel, isActive: Bool = true) -> some View {
        confirmationDialog(
            Text("clusters.deleteAll.title", bundle: .module),
            isPresented: Binding(
                get: { isActive && viewModel.pendingDeleteAllClusterID != nil },
                set: { if !$0 { viewModel.pendingDeleteAllClusterID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                viewModel.confirmDeleteAll()
            } label: {
                Text("clusters.deleteAll.confirm", bundle: .module)
            }
        } message: {
            Text("clusters.deleteAll.message", bundle: .module)
        }
    }
}
