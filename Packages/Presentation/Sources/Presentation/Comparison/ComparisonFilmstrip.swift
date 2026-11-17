import SwiftUI

/// The strip of the group's photos under the pager. Tapping one shows it; the shown photo stays scrolled into view.
struct ComparisonFilmstrip: View {
    let viewModel: PhotoComparisonViewModel

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 52

    /// A horizontal strip; `ScrollViewReader` keeps the current photo centred.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(viewModel.memberIDs, id: \.self) { assetID in
                        cell(assetID)
                            .id(assetID)
                    }
                }
                .padding(8)
            }
            .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)
            .onChange(of: viewModel.focusedID, initial: true) { _, focused in
                guard let focused else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(focused, anchor: .center)
                }
            }
        }
        .frame(height: side + 16)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One thumbnail: framed when shown, dimmed with a checkmark when selected, starred when Best.
    private func cell(_ assetID: String) -> some View {
        let isShown = assetID == viewModel.shownCurrentID
            || (viewModel.showsSideBySide && assetID == viewModel.shownSecondaryID)
        let isSelected = viewModel.isSelected(assetID)
        return Button {
            viewModel.show(assetID)
        } label: {
            AsyncThumbnail(
                assetID: assetID,
                pixelSize: CGSize(width: side * displayScale, height: side * displayScale),
                isMissing: viewModel.isMissing(assetID),
                loader: viewModel.thumbnails
            )
            .frame(width: side, height: side)
            .opacity(isSelected ? 0.55 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white, lineWidth: isShown ? 3 : 0)
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .padding(2)
                }
            }
            .overlay(alignment: .topLeading) {
                if viewModel.isBest(assetID) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.accessibilityLabel(for: assetID))
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityHint(Text("compare.filmstrip.hint", bundle: .module))
    }
}
