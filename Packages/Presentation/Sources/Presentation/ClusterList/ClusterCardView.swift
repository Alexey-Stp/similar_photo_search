import Domain
import SwiftUI

/// One group, photo first: every photo in a grid that fills the card's width (the suggested keeper first, with the
/// **Best** badge), then a footer with the date, the count, the group's total size and the size selected for
/// deletion, which opens the comparison. Photos selected for deletion are dimmed and carry a red checkmark.
/// Tapping a photo toggles it.
///
/// `Equatable` on its content, so the list re-renders a card only when its own data changed. The selection is read
/// from the cluster's own `ClusterSelectionState`, so a toggle re-renders only this card.
struct ClusterCardView: View, Equatable {
    let card: ClusterCardModel
    let state: ClusterSelectionState
    let pixelSize: CGSize
    let thumbnails: any ThumbnailLoading
    let onToggle: (String) -> Void
    let onCompare: () -> Void

    @ScaledMetric(relativeTo: .body) private var minimumTile: CGFloat = 96

    /// Equal when the content, the selection object and the size are; the closures are ignored.
    nonisolated static func == (lhs: ClusterCardView, rhs: ClusterCardView) -> Bool {
        lhs.card == rhs.card && lhs.state === rhs.state && lhs.pixelSize == rhs.pixelSize
    }

    /// The photos above the footer.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            grid
            footer
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sensoryFeedback(.selection, trigger: state.selectedIDs)
        .accessibilityElement(children: .contain)
    }

    /// All photos, the keeper first, in as many square columns as fit.
    private var grid: some View {
        let positions = Dictionary(uniqueKeysWithValues: card.photos.enumerated().map { ($1.id, $0 + 1) })
        let keeper = card.photos.first { $0.id == state.keeperID }
        let ordered = (keeper.map { [$0] } ?? []) + card.photos.filter { $0.id != keeper?.id }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumTile), spacing: 6)], spacing: 6) {
            ForEach(ordered) { photo in
                thumbnail(photo, position: positions[photo.id] ?? 1)
            }
        }
    }

    /// Date, count, sizes and chips; tapping it opens the comparison.
    private var footer: some View {
        Button(action: onCompare) {
            HStack(alignment: .center, spacing: 8) {
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
        .accessibilityHint(Text("clusters.header.hint", bundle: .module))
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

    /// One square photo with its overlays, VoiceOver label and actions; tapping it toggles the photo.
    private func thumbnail(_ photo: ClusterCardModel.Photo, position: Int) -> some View {
        let isSelected = state.isSelected(photo.id)
        let isBest = state.keeperID == photo.id
        return Button {
            onToggle(photo.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncThumbnail(
                        assetID: photo.id,
                        pixelSize: pixelSize,
                        isMissing: photo.isMissing,
                        loader: thumbnails
                    )
                }
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        SelectionCheck()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isBest {
                        BestBadge()
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(photo.isMissing)
        .accessibilityLabel(ClusterCardModel.photoAccessibilityLabel(
            position: position,
            count: card.photos.count,
            dateText: photo.date.map(ClusterCardModel.photoDateText),
            status: ClusterCardModel.PhotoStatus(isSelected: isSelected, isMissing: photo.isMissing),
            isBest: isBest
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("clusters.action.toggle", bundle: .module)) { onToggle(photo.id) }
        .accessibilityAction(named: Text("clusters.action.compare", bundle: .module)) { onCompare() }
    }
}
