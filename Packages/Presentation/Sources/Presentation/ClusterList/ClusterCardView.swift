import Domain
import SwiftUI

/// One group in the list. By default its photos sit in **one line** (keeper first, scrolling sideways in a big
/// group); the expand button shows every photo in a grid. Under them, a footer with the date, the count, the group's
/// total size and the size selected for deletion opens the group's own page. Tapping a photo toggles it.
///
/// `Equatable` on its content, so the list re-renders a card only when its own data changed. The selection is read
/// from the cluster's own `ClusterSelectionState`, so a toggle re-renders only this card.
struct ClusterCardView: View, Equatable {
    let card: ClusterCardModel
    let state: ClusterSelectionState
    let pixelSize: CGSize
    let thumbnails: any ThumbnailLoading
    let onToggle: (String) -> Void
    /// Opens the group's own page.
    let onOpen: () -> Void
    /// Opens the full-screen comparison (VoiceOver action).
    let onCompare: () -> Void

    @State private var isExpanded = false
    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 96

    /// Equal when the content, the selection object and the size are; the closures are ignored.
    nonisolated static func == (lhs: ClusterCardView, rhs: ClusterCardView) -> Bool {
        lhs.card == rhs.card && lhs.state === rhs.state && lhs.pixelSize == rhs.pixelSize
    }

    /// The photos above the footer.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isExpanded {
                grid
            } else {
                strip
            }
            footer
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sensoryFeedback(.selection, trigger: state.selectedIDs)
        .accessibilityElement(children: .contain)
    }

    /// The members, keeper first, with their 1-based positions in the group.
    private var ordered: [(photo: ClusterCardModel.Photo, position: Int)] {
        let indexed = card.photos.enumerated().map { (photo: $1, position: $0 + 1) }
        let keeper = indexed.first { $0.photo.id == state.keeperID }
        return (keeper.map { [$0] } ?? []) + indexed.filter { $0.photo.id != keeper?.photo.id }
    }

    /// One line of photos that scrolls sideways.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(ordered, id: \.photo.id) { item in
                    tile(item.photo, position: item.position)
                        .frame(width: tileSide, height: tileSide)
                }
            }
        }
        .frame(height: tileSide)
    }

    /// Every photo in as many columns as fit.
    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSide), spacing: 6)], spacing: 6) {
            ForEach(ordered, id: \.photo.id) { item in
                tile(item.photo, position: item.position)
            }
        }
    }

    private func tile(_ photo: ClusterCardModel.Photo, position: Int) -> some View {
        ClusterPhotoTile(
            photo: photo,
            position: position,
            count: card.photos.count,
            state: state,
            pixelSize: pixelSize,
            thumbnails: thumbnails,
            onToggle: onToggle,
            onCompare: onCompare
        )
    }

    /// Date, count, sizes and chips (tapping them opens the group's page), and the expand button.
    private var footer: some View {
        HStack(alignment: .center, spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("group.open.hint", bundle: .module))
            if card.photos.count > 1 {
                expandButton
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let date = card.date {
                Text(ClusterCardModel.headerDateText(date))
                    .font(.headline)
            }
            countAndSize
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let selected = card.bytes(of: state.selectedIDs), selected > 0 {
                Label {
                    Text("clusters.row.toDelete \(Self.format(selected))", bundle: .module)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
            }
            chips
                .padding(.top, 6)
        }
    }

    /// Shows every photo, or one line again.
    private var expandButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Label {
                Text(isExpanded ? "group.collapse" : "group.showAll", bundle: .module)
            } icon: {
                Image(systemName: isExpanded ? "rectangle.compress.vertical" : "square.grid.2x2")
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.fill.tertiary, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// "4 photos · 18 MB", or the count alone while sizes load.
    private var countAndSize: Text {
        let count = Text("clusters.row.photos \(card.photos.count)", bundle: .module)
        guard let total = card.totalBytes else { return count }
        return count + Text(verbatim: " · ") + Text(Self.format(total))
    }

    /// A size in bytes as "18 MB" (locale dependent).
    static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    @ViewBuilder private var chips: some View {
        if card.needsReview || card.isExactDuplicate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chipLabels }
                VStack(alignment: .leading, spacing: 4) { chipLabels }
            }
        }
    }

    @ViewBuilder private var chipLabels: some View {
        if card.needsReview {
            ClusterChip(text: Text("selection.reviewRecommended", bundle: .module), systemImage: "eye", tint: .orange)
        }
        if card.isExactDuplicate {
            ClusterChip(
                text: Text("clusters.exactDuplicate", bundle: .module),
                systemImage: "equal.square",
                tint: .blue
            )
        }
    }
}
