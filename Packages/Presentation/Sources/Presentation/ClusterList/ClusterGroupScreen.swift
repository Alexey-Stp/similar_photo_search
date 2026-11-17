import SwiftUI

/// One group on its own page, for working through just that group: every photo in a grid (tap to select or keep),
/// the group's size and the size selected, Compare (the full-screen comparison) and a floating bar that deletes the
/// photos selected in this group, through the usual review sheet and system alert.
///
/// When a deletion renames the group (its naming photo was deleted), the page follows the survivors.
struct ClusterGroupScreen: View {
    let viewModel: ClusterListViewModel
    let onCompare: (String) -> Void

    @State private var clusterID: String
    @State private var membersBeforeDeletion: [String] = []
    @State private var deletionRequest: ClusterListViewModel.DeletionRequest?
    @ScaledMetric(relativeTo: .body) private var minimumTile: CGFloat = 104

    init(viewModel: ClusterListViewModel, clusterID: String, onCompare: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.onCompare = onCompare
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
        .deleteAllConfirmation(viewModel)
        .sheet(
            item: $deletionRequest,
            onDismiss: followRenamedGroup,
            content: { request in
                DeletionSheet(request: request) { deletionRequest = nil }
            }
        )
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
                Button {
                    onCompare(clusterID)
                } label: {
                    Label {
                        Text("clusters.action.compare", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.split.2x1")
                    }
                }
                .buttonStyle(HomeInkButtonStyle())
                .accessibilityHint(Text("clusters.header.hint", bundle: .module))
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            deleteBar(card: card, state: state)
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

    /// "2 photos · 12 MB" selected in this group, and Delete for exactly those photos.
    private func deleteBar(card: ClusterCardModel, state: ClusterSelectionState) -> some View {
        let selected = card.photos.map(\.id).filter(state.isSelected)
        let bytes = card.bytes(of: Set(selected))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("deletion.review.strip \(selected.count)", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                if let bytes, bytes > 0 {
                    Text(ClusterCardView.format(bytes))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                membersBeforeDeletion = card.photos.map(\.id)
                viewModel.selection.estimateSizes(of: selected)
                deletionRequest = ClusterListViewModel.DeletionRequest(assetIDs: selected)
            } label: {
                SelectionDeleteLabel()
            }
            .buttonStyle(.plain)
            .opacity(selected.isEmpty ? 0.4 : 1)
            .disabled(selected.isEmpty)
            .accessibilityHint(Text("selection.delete.hint", bundle: .module))
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    /// After a deletion that renamed or removed the group, show the group that holds the survivors, if any.
    private func followRenamedGroup() {
        defer { membersBeforeDeletion = [] }
        guard viewModel.selection.state(for: clusterID) == nil else { return }
        let selection = viewModel.selection
        if let survivor = membersBeforeDeletion.lazy.compactMap({ selection.clusterID(containing: $0) }).first {
            clusterID = survivor
        }
    }
}
