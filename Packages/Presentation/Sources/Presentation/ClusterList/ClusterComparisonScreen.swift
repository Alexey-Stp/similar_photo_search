import Domain
import SwiftUI

/// Interim comparison of one group: its photos one below the other at a larger size, with the same badges and
/// toggle as the card. SPS-22 replaces it with the full-screen pager, zoom and info panel.
struct ClusterComparisonScreen: View {
    let viewModel: ClusterListViewModel
    let clusterID: String

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            if let card = viewModel.card(for: clusterID), let state = viewModel.selection.state(for: clusterID) {
                LazyVStack(spacing: 16) {
                    ForEach(Array(card.photos.enumerated()), id: \.element.id) { index, photo in
                        photoRow(photo, position: index + 1, count: card.photos.count, state: state)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(Text("compare.title", bundle: .module))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SelectionSummaryBar(store: viewModel.selection)
        }
    }

    private func photoRow(
        _ photo: ClusterCardModel.Photo,
        position: Int,
        count: Int,
        state: ClusterSelectionState
    ) -> some View {
        let isSelected = state.isSelected(photo.id)
        let isBest = state.keeperID == photo.id
        let side: CGFloat = 320
        return Button {
            viewModel.toggle(photo.id, in: clusterID)
        } label: {
            AsyncThumbnail(
                assetID: photo.id,
                pixelSize: CGSize(width: side * displayScale, height: side * displayScale),
                isMissing: photo.isMissing,
                loader: viewModel.thumbnails
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: side)
            .opacity(isSelected ? 0.6 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(.largeTitle)
                        .padding(8)
                }
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Text("selection.keepBest", bundle: .module)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(.green, in: Capsule())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(photo.isMissing)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(ClusterCardModel.photoAccessibilityLabel(
            position: position,
            count: count,
            dateText: photo.date.map(ClusterCardModel.photoDateText),
            status: ClusterCardModel.PhotoStatus(isSelected: isSelected, isMissing: photo.isMissing),
            isBest: isBest
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("clusters.action.toggle", bundle: .module))
    }
}
