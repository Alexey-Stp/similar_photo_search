import SwiftUI

/// What will be deleted, before anything is: count and estimated size, number of groups, a thumbnail strip, the
/// Recently Deleted note and the destructive confirm button. Cancel closes the sheet without changing anything.
struct DeletionReviewView: View {
    let viewModel: DeletionViewModel
    let onCancel: () -> Void

    @Environment(\.displayScale) private var displayScale

    /// Thumbnails in the strip are this many points high and wide.
    static let thumbnailSide: CGFloat = 64

    /// The summary, strip, note and confirm button.
    var body: some View {
        let summary = viewModel.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.text)
                        .font(.headline)
                        .accessibilityAddTraits(.updatesFrequently)
                    Text("deletion.review.groups \(viewModel.groupCount)", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                thumbnailStrip
                Label {
                    Text("deletion.review.note", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "trash.circle")
                }
                .font(.subheadline)
                Button(role: .destructive) {
                    Task { await viewModel.confirm() }
                } label: {
                    Text("deletion.review.confirm \(summary.photoCount)", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(summary.photoCount == 0)
                .accessibilityHint(Text("deletion.review.confirm.hint", bundle: .module))
            }
            .padding()
        }
        .navigationTitle(Text("deletion.review.title", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onCancel) {
                    Text("deletion.review.cancel", bundle: .module)
                }
            }
        }
    }

    /// The photos to delete, scrolling sideways; thumbnails load only while visible.
    private var thumbnailStrip: some View {
        let side = Self.thumbnailSide
        let pixels = CGSize(width: side * displayScale, height: side * displayScale)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(viewModel.assetIDs, id: \.self) { assetID in
                    AsyncThumbnail(
                        assetID: assetID,
                        pixelSize: pixels,
                        isMissing: false,
                        loader: viewModel.thumbnails
                    )
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("deletion.review.strip \(viewModel.assetIDs.count)", bundle: .module))
    }
}
