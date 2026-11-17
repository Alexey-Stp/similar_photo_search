import SwiftUI

/// One group on its own page, for working through just that group: every photo in a grid (tap to select or keep),
/// the group's size and the size selected, Compare (the full-screen comparison) and a floating bar that deletes the
/// photos selected in this group, through the usual review sheet and system alert.
///
/// When a deletion renames the group (its naming photo was deleted), the page follows the survivors.
struct ClusterGroupScreen: View {
    let viewModel: ClusterListViewModel
    let onCompare: (String) -> Void
    /// Whether this page is on top and presents "Delete every photo of this group?" (not under the comparison).
    var isDialogActive = true

    @State private var clusterID: String
    @State private var deletionRequest: ClusterListViewModel.DeletionRequest?
    @ScaledMetric(relativeTo: .body) private var minimumTile: CGFloat = 104

    init(
        viewModel: ClusterListViewModel,
        clusterID: String,
        isDialogActive: Bool = true,
        onCompare: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.onCompare = onCompare
        self.isDialogActive = isDialogActive
        _clusterID = State(initialValue: clusterID)
    }

    var body: some View {
        Group {
            if let card = viewModel.card(for: clusterID), let state = viewModel.selection.state(for: clusterID) {
                content(card: card, state: state)
            } else {
                ContentUnavailableView {
                    Text("compare.groupGone", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("group.title", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .deleteAllConfirmation(viewModel, isActive: isDialogActive)
        .sheet(item: $deletionRequest) { request in
            DeletionSheet(request: request) { deletionRequest = nil }
        }
        .onChange(of: memberIDs) { previous, current in
            // A deletion here or in Compare renamed or removed the group: follow its survivors.
            if current.isEmpty, !previous.isEmpty {
                followRenamedGroup(from: previous)
            }
        }
    }

    private func content(card: ClusterCardModel, state: ClusterSelectionState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(card)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTile), spacing: 6)], spacing: 6) {
                    ForEach(card.photos) { photo in
                        ClusterPhotoTile(
                            photo: photo,
                            position: (card.photos.firstIndex(of: photo) ?? 0) + 1,
                            count: card.photos.count,
                            state: state,
                            pixelSize: viewModel.pixelSize,
                            thumbnails: viewModel.thumbnails,
                            onToggle: { viewModel.toggle($0, in: clusterID) },
                            onCompare: { onCompare(clusterID) }
                        )
                    }
                }
            }
            .padding()
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(card: card)
        }
    }

    /// Date, count and sizes of the group.
    private func header(_ card: ClusterCardModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = card.date {
                Text(ClusterCardModel.headerDateText(date))
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            HStack(spacing: 8) {
                HomeStatTile(value: card.photos.count, titleKey: "home.stat.photos")
                if let total = card.totalBytes {
                    HomeStatTile(text: ClusterCardView.format(total), titleKey: "home.stat.totalSize")
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// Compare, and Delete (with the count) for exactly the photos selected in this group.
    private func bottomBar(card: ClusterCardModel) -> some View {
        let selected = card.photos.map(\.id).filter { viewModel.selection.isSelected($0) }
        return HStack(spacing: 0) {
            BarItem(titleKey: "clusters.action.compare", systemImage: "rectangle.split.2x1") {
                onCompare(clusterID)
            }
            .accessibilityHint(Text("clusters.header.hint", bundle: .module))
            BarItem(
                titleKey: "selection.delete.short",
                systemImage: "trash.fill",
                tint: .red,
                badge: selected.count
            ) {
                viewModel.selection.estimateSizes(of: selected)
                deletionRequest = ClusterListViewModel.DeletionRequest(assetIDs: selected)
            }
            .disabled(selected.isEmpty)
            .accessibilityLabel(Text("deletion.review.confirm \(selected.count)", bundle: .module))
            .accessibilityHint(Text("selection.delete.hint", bundle: .module))
        }
        .floatingBar()
        .accessibilityElement(children: .contain)
    }

    /// The members of the group shown, empty once it is gone.
    private var memberIDs: [String] {
        viewModel.selection.state(for: clusterID)?.memberIDs ?? []
    }

    /// After a deletion that renamed the group (its naming photo was deleted), show the group that holds the
    /// survivors; keep the current ID when it still exists.
    private func followRenamedGroup(from previous: [String]) {
        guard viewModel.selection.state(for: clusterID) == nil else { return }
        let selection = viewModel.selection
        if let survivor = previous.lazy.compactMap({ selection.clusterID(containing: $0) }).first {
            clusterID = survivor
        }
    }
}
