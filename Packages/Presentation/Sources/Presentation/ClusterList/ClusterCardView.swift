import Domain
import SwiftUI

/// One group: a header (date, count, "Review recommended") that opens the comparison, and a horizontal strip of
/// thumbnails with the **Best** badge on the kept photo and a checkmark and dimming on the photos selected for
/// deletion. Tapping a thumbnail toggles it.
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

    nonisolated static func == (lhs: ClusterCardView, rhs: ClusterCardView) -> Bool {
        lhs.card == rhs.card && lhs.state === rhs.state && lhs.pixelSize == rhs.pixelSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(card.photos.enumerated()), id: \.element.id) { index, photo in
                        thumbnail(photo, position: index + 1)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(.selection, trigger: state.selectedIDs)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Button(action: onCompare) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if let date = card.date {
                        Text(ClusterCardModel.headerDateText(date))
                            .font(.headline)
                    }
                    Text("clusters.row.photos \(card.photos.count)", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    chips
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("clusters.header.hint", bundle: .module))
    }

    @ViewBuilder private var chips: some View {
        if card.needsReview || card.isExactDuplicate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chipLabels }
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

    private func thumbnail(_ photo: ClusterCardModel.Photo, position: Int) -> some View {
        let isSelected = state.isSelected(photo.id)
        let isBest = state.keeperID == photo.id
        let side = ClusterListViewModel.thumbnailSide
        return Button {
            onToggle(photo.id)
        } label: {
            AsyncThumbnail(assetID: photo.id, pixelSize: pixelSize, isMissing: photo.isMissing, loader: thumbnails)
                .frame(width: side, height: side)
                .overlay {
                    if isSelected {
                        Color.black.opacity(0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .font(.title3)
                            .padding(4)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isBest {
                        BestBadge()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(photo.isMissing)
        .accessibilityLabel(ClusterCardModel.photoAccessibilityLabel(
            position: position,
            count: card.photos.count,
            dateText: photo.date.map(ClusterCardModel.photoDateText),
            isSelected: isSelected,
            isBest: isBest,
            isMissing: photo.isMissing
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("clusters.action.toggle", bundle: .module)) { onToggle(photo.id) }
        .accessibilityAction(named: Text("clusters.action.compare", bundle: .module)) { onCompare() }
    }
}

/// The "Best" badge on the suggested keeper.
private struct BestBadge: View {
    var body: some View {
        Text("clusters.badge.best", bundle: .module)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(.green, in: Capsule())
            .padding(4)
            .accessibilityHidden(true)
    }
}

/// A small coloured label in the card header.
private struct ClusterChip: View {
    let text: Text
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(tint)
    }
}
