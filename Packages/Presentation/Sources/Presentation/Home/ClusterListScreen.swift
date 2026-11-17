import Domain
import SwiftUI

/// The groups of similar photos, opened from Home ("Review", "Review now").
///
/// - Cards in a `LazyVStack`; the scroll position is bound to the top visible row, so groups inserted above it
///   (newer photos found by a live rescan) don't move anything on screen.
/// - While a scan runs, a compact progress bar stays at the top, new groups are appended, and the list ends with
///   "Still scanning… 4,210 of 18,000".
/// - The bottom bar has Smart Select All, Deselect All, the summary and "Delete N photos (X MB)".
struct ClusterListScreen: View {
    let viewModel: ClusterListViewModel
    let onCompare: (String) -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var topRowID: String?

    /// The list with its bars, toolbar, dialog and lifecycle hooks.
    var body: some View {
        let scan = viewModel.scan
        list
        .navigationTitle(Text("clusters.title", bundle: .module))
        .toolbar { ClusterListToolbar(viewModel: viewModel) }
        .safeAreaInset(edge: .top, spacing: 0) {
            if scan.isScanning {
                ScanProgressBar(scan: scan)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionSummaryBar(store: scan.selection, excluding: viewModel.missingAssetIDs) {
                viewModel.requestDeletion()
            }
        }
        .confirmationDialog(
            Text("clusters.deleteAll.title", bundle: .module),
            isPresented: deleteAllBinding,
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
        .sheet(item: deletionBinding) { request in
            DeletionSheet(request: request) { viewModel.deletionRequest = nil }
        }
        .onChange(of: scan.clusterRevision, initial: true) { viewModel.clustersChanged() }
        .onChange(of: displayScale, initial: true) { viewModel.displayScaleChanged(displayScale) }
        .onChange(of: viewModel.rows.first, initial: true) { _, first in
            // Pin the scroll position to a row as soon as there is one, so rows inserted above don't push it down.
            if topRowID == nil {
                topRowID = first
            }
        }
        .task { await viewModel.observeLibraryChanges() }
        .onAppear { scan.scanScreenAppeared() }
        .onDisappear {
            scan.scanScreenDisappeared()
            viewModel.stopPrefetching()
        }
    }

    /// The cards, the scanning footer, and the empty-filter message.
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.rows, id: \.self) { clusterID in
                    row(clusterID)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
            .padding(.top, 8)
            footer
        }
        .scrollPosition(id: $topRowID, anchor: .top)
        .modifier(ScrollInteractionTracking { viewModel.interactionChanged(isInteracting: $0) })
        .overlay {
            if viewModel.rows.isEmpty, !viewModel.scan.isScanning {
                ContentUnavailableView {
                    Text("clusters.filter.empty", bundle: .module)
                }
            }
        }
    }

    /// The card of one group; appearing moves the prefetch window.
    @ViewBuilder private func row(_ clusterID: String) -> some View {
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

    @ViewBuilder private var footer: some View {
        if let text = viewModel.scanFooterText {
            HStack(spacing: 8) {
                ProgressView()
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .accessibilityElement(children: .combine)
        }
    }

    /// Presents the deletion flow (SPS-25) for the last tap on "Delete N photos"; cleared when the sheet closes.
    private var deletionBinding: Binding<ClusterListViewModel.DeletionRequest?> {
        Binding(
            get: { viewModel.deletionRequest },
            set: { viewModel.deletionRequest = $0 }
        )
    }

    /// Presents the delete-all dialog while a group waits for it.
    private var deleteAllBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeleteAllClusterID != nil },
            set: { if !$0 { viewModel.pendingDeleteAllClusterID = nil } }
        )
    }
}

/// The "Filter and sort" menu.
private struct ClusterListToolbar: ToolbarContent {
    @Bindable var viewModel: ClusterListViewModel

    /// A menu with the filter and sort pickers.
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(selection: $viewModel.filter) {
                    Text("clusters.filter.all", bundle: .module).tag(ClusterListViewModel.Filter.all)
                    Text("clusters.filter.needsReview", bundle: .module).tag(ClusterListViewModel.Filter.needsReview)
                    Text("clusters.filter.exactDuplicates", bundle: .module)
                        .tag(ClusterListViewModel.Filter.exactDuplicates)
                } label: {
                    Text("clusters.filter", bundle: .module)
                }
                Picker(selection: $viewModel.sort) {
                    Text("clusters.sort.date", bundle: .module).tag(ClusterListViewModel.Sort.date)
                    Text("clusters.sort.size", bundle: .module).tag(ClusterListViewModel.Sort.reclaimableSize)
                } label: {
                    Text("clusters.sort", bundle: .module)
                }
            } label: {
                Label {
                    Text("clusters.filterAndSort", bundle: .module)
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

/// Reports whether the user is touching or scrolling the list: the scroll phase on iOS 18, a drag on iOS 17.
private struct ScrollInteractionTracking: ViewModifier {
    let onChange: (Bool) -> Void
    @GestureState private var isDragging = false

    /// Reports the interaction through `onChange`.
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                onChange(phase != .idle)
            }
        } else {
            content
                .simultaneousGesture(DragGesture().updating($isDragging) { _, state, _ in state = true })
                .onChange(of: isDragging) { _, dragging in onChange(dragging) }
        }
    }
}

#if DEBUG
#Preview("Groups while scanning") {
    let list = ClusterListViewModel.preview()
    return NavigationStack {
        ClusterListScreen(viewModel: list) { _ in }
    }
    .task { await list.scan.startScan() }
}

#Preview("Groups, dark, AX3") {
    NavigationStack {
        ClusterListScreen(viewModel: .preview()) { _ in }
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
#endif
