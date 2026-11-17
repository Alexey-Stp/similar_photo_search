import SwiftUI

/// The groups found, on Home under the summary card: a header with "See All" (the group list), a Date / Size sort
/// switch, then one tile per group: its best photo with the group's full size, the size that would be freed and its
/// photo count underneath. Tapping a tile opens the group's own page.
struct HomeGroupsSection: View {
    @Bindable var list: ClusterListViewModel
    let onOpen: (String) -> Void
    let onSeeAll: () -> Void

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var minimumTile: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("home.groups.title", bundle: .module)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onSeeAll) {
                    Text("home.groups.seeAll", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityHint(Text("home.review.hint", bundle: .module))
            }
            Picker(selection: $list.sort) {
                Text("home.groups.sort.date", bundle: .module).tag(ClusterListViewModel.Sort.date)
                Text("home.groups.sort.size", bundle: .module).tag(ClusterListViewModel.Sort.reclaimableSize)
            } label: {
                Text("clusters.sort", bundle: .module)
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTile), spacing: 12)], spacing: 16) {
                ForEach(list.rows, id: \.self) { clusterID in
                    if let card = list.card(for: clusterID), let state = list.selection.state(for: clusterID) {
                        HomeGroupTile(
                            card: card,
                            state: state,
                            freedBytes: list.reclaimableBytes(of: clusterID),
                            pixelSize: tilePixels,
                            thumbnails: list.thumbnails
                        ) { onOpen(clusterID) }
                        .onAppear { list.rowAppeared(clusterID) }
                    }
                }
            }
        }
        .onChange(of: displayScale, initial: true) { list.displayScaleChanged(displayScale) }
    }

    /// Tiles are about twice a list thumbnail wide, so they request twice the pixels.
    private var tilePixels: CGSize {
        CGSize(width: list.pixelSize.width * 2, height: list.pixelSize.height * 2)
    }
}

/// One group on Home: its best photo (with the photo count on it), then the group's full size and the size that
/// would be freed. A button that opens the group's page.
private struct HomeGroupTile: View {
    let card: ClusterCardModel
    let state: ClusterSelectionState
    /// What deleting every photo but the suggested keeper would free; `nil` while sizes load.
    let freedBytes: Int64?
    let pixelSize: CGSize
    let thumbnails: any ThumbnailLoading
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.totalBytes.map(ClusterCardView.format) ?? "–")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    if let freed = freedBytes, freed > 0 {
                        Text("home.group.toFree \(ClusterCardView.format(freed))", bundle: .module)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("clusters.row.photos \(card.photos.count)", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("group.open.hint", bundle: .module))
    }

    /// The best photo (else the first), square, with the count in a capsule.
    private var cover: some View {
        let coverID = state.keeperID ?? card.photos.first?.id ?? ""
        let isMissing = card.photos.first { $0.id == coverID }?.isMissing ?? false
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncThumbnail(assetID: coverID, pixelSize: pixelSize, isMissing: isMissing, loader: thumbnails)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Label {
                    Text(card.photos.count, format: .number)
                } icon: {
                    Image(systemName: "square.on.square")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(8)
                .accessibilityHidden(true)
            }
    }
}
