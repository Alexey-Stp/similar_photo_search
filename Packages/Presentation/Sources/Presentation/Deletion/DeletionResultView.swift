import SwiftUI

/// The result of a deletion: what was deleted and how much space it frees, the photos that could not be deleted
/// with their reasons (they stay in their groups, selectable), and "Open Photos" when the system can open it.
struct DeletionResultView: View {
    let outcome: DeletionOutcome
    let isPartial: Bool
    let viewModel: DeletionViewModel
    let onDone: () -> Void

    @Environment(\.displayScale) private var displayScale

    /// The message, the failed photos and the actions.
    var body: some View {
        List {
            Section {
                Label {
                    Text(isPartial ? outcome.partialText : outcome.successText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: isPartial ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(isPartial ? Color.orange : Color.green)
                }
                .font(.headline)
                if isPartial, outcome.deletedCount > 0 {
                    Text("deletion.result.spaceNote", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !outcome.failures.isEmpty {
                Section {
                    ForEach(Array(outcome.failures.enumerated()), id: \.element.id) { index, failure in
                        failureRow(failure, position: index + 1)
                    }
                } header: {
                    Text("deletion.failures.header", bundle: .module)
                } footer: {
                    Text("deletion.failures.footer", bundle: .module)
                }
            }
            if viewModel.canOpenPhotos, outcome.deletedCount > 0 {
                Section {
                    Button {
                        viewModel.openPhotos()
                    } label: {
                        Label {
                            Text("deletion.openPhotos", bundle: .module)
                        } icon: {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }
                    .accessibilityHint(Text("deletion.openPhotos.hint", bundle: .module))
                }
            }
        }
        .navigationTitle(Text(title, bundle: .module))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onDone) {
                    Text("deletion.done", bundle: .module)
                }
            }
        }
    }

    /// "Photos Deleted" or "Some Photos Not Deleted".
    private var title: LocalizedStringKey {
        isPartial ? "deletion.result.partialTitle" : "deletion.result.title"
    }

    /// A photo that was not deleted: its thumbnail and the reason.
    private func failureRow(_ failure: DeletionOutcome.Failure, position: Int) -> some View {
        let side = DeletionReviewView.thumbnailSide
        return HStack(spacing: 12) {
            AsyncThumbnail(
                assetID: failure.id,
                pixelSize: CGSize(width: side * displayScale, height: side * displayScale),
                isMissing: failure.reason == .unavailable,
                loader: viewModel.thumbnails
            )
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(failure.reasonText.capitalizedSentence)
                .font(.body)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("deletion.failure.label \(position) \(failure.reasonText)", bundle: .module))
    }
}

private extension String {
    /// The string with its first letter uppercased ("shared album" → "Shared album").
    var capitalizedSentence: String {
        prefix(1).uppercased() + dropFirst()
    }
}
