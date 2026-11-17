import SwiftUI

/// What will be deleted, before anything is: the estimated size as a large figure, the counts, every photo in a
/// grid, the Recently Deleted note and the red confirm button. Cancel closes the sheet without changing anything.
struct DeletionReviewView: View {
    let viewModel: DeletionViewModel
    let onCancel: () -> Void

    @Environment(\.displayScale) private var displayScale

    /// Thumbnails are at least this many points wide (also the result screen's strip).
    static let thumbnailSide: CGFloat = 64

    /// The size as a large figure, the counts, the photos in a grid, the note and the confirm button.
    var body: some View {
        let summary = viewModel.summary
        ScrollView {
            VStack(spacing: 20) {
                header(summary)
                thumbnailGrid
                Label {
                    Text("deletion.review.note", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.tint)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(spacing: 10) {
                    Button(role: .destructive) {
                        Task { await viewModel.confirm() }
                    } label: {
                        Label {
                            Text("deletion.review.confirm \(summary.photoCount)", bundle: .module)
                        } icon: {
                            Image(systemName: "trash.fill")
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(SelectionSummaryBar.deleteRed, in: Capsule())
                        .opacity(summary.photoCount == 0 ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(summary.photoCount == 0)
                    .accessibilityHint(Text("deletion.review.confirm.hint", bundle: .module))
                    Text("deletion.review.systemNote", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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

    /// "214 MB" in large rounded type (with "At least — some sizes are unavailable" when it is a lower bound) over
    /// "38 photos to delete" and "From 9 groups"; the count alone while the size is unknown. VoiceOver reads the
    /// summary sentence, which says "at least" itself.
    private func header(_ summary: DeletionSummary) -> some View {
        VStack(spacing: 4) {
            if let bytes = summary.estimatedBytes {
                HomeHeroNumber(text: bytes.formatted(.byteCount(style: .file)))
                if summary.isLowerBound {
                    Text("deletion.review.lowerBound", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text("deletion.review.strip \(summary.photoCount)", bundle: .module)
                .font(.headline)
            Text("deletion.review.groups \(viewModel.groupCount)", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(summary.text))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The photos to delete in a grid; thumbnails load only while visible.
    private var thumbnailGrid: some View {
        let pixels = CGSize(width: Self.thumbnailSide * displayScale, height: Self.thumbnailSide * displayScale)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.thumbnailSide), spacing: 6)], spacing: 6) {
            ForEach(viewModel.assetIDs, id: \.self) { assetID in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AsyncThumbnail(
                            assetID: assetID,
                            pixelSize: pixels,
                            isMissing: false,
                            loader: viewModel.thumbnails
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("deletion.review.strip \(viewModel.assetIDs.count)", bundle: .module))
    }
}
