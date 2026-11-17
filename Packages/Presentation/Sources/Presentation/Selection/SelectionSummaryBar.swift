import Domain
import SwiftUI

/// Bottom bar with the global "Smart Select All" and "Deselect All" actions and what would be deleted right now
/// ("38 photos, about 214 MB will be deleted"), and with `onDelete` the "Delete N photos (X MB)" button, disabled
/// while nothing is selected. It never deletes anything itself: `onDelete` starts the deletion flow (SPS-25).
///
/// Reads only the store's totals, so toggling a photo re-renders this bar and that photo's cluster, nothing else.
public struct SelectionSummaryBar: View {
    private let store: SelectionStore
    private let excluded: Set<String>
    private let onDelete: (() -> Void)?

    /// Creates the bar for a store.
    /// - Parameters:
    ///   - excluding: Selected photos to leave out of the count and size (photos deleted outside the app).
    ///   - onDelete: Called by the delete button; without it the bar has no delete button.
    public init(store: SelectionStore, excluding: Set<String> = [], onDelete: (() -> Void)? = nil) {
        self.store = store
        excluded = excluding
        self.onDelete = onDelete
    }

    /// What the bar shows. Reads `store.summary` first, so the bar also updates when sizes arrive.
    private var summary: DeletionSummary {
        let base = store.summary
        return excluded.isEmpty ? base : store.summary(excluding: excluded)
    }

    /// "Delete 38 photos (214 MB)"; "(at least 214 MB)" when some sizes are unavailable; without the size while
    /// it is unknown.
    static func deleteTitle(for summary: DeletionSummary) -> String {
        guard let bytes = summary.estimatedBytes, summary.photoCount > 0 else {
            return String(localized: "selection.delete.noSize \(summary.photoCount)", bundle: .module)
        }
        let size = bytes.formatted(.byteCount(style: .file))
        if summary.isLowerBound {
            return String(localized: "selection.delete.atLeast \(summary.photoCount) \(size)", bundle: .module)
        }
        return String(localized: "selection.delete \(summary.photoCount) \(size)", bundle: .module)
    }

    /// The summary, the bulk actions and, with `onDelete`, the delete button.
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Text(Self.deleteTitle(for: summary))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(summary.photoCount == 0)
                .accessibilityHint(Text("selection.delete.hint", bundle: .module))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        Button {
            store.selectSmartAll()
        } label: {
            Text("selection.smartSelectAll", bundle: .module)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(Text("selection.smartSelectAll.hint", bundle: .module))
        Button {
            store.deselectAll()
        } label: {
            Text("selection.deselectAll", bundle: .module)
        }
        .buttonStyle(.bordered)
        .disabled(store.selectedCount == 0)
        .accessibilityHint(Text("selection.deselectAll.hint", bundle: .module))
    }
}

#if DEBUG
#Preview("Light") {
    SelectionSummaryBar(store: .preview()) {}
}

#Preview("Nothing selected") {
    SelectionSummaryBar(store: .empty()) {}
}

#Preview("Dark") {
    SelectionSummaryBar(store: .preview())
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    SelectionSummaryBar(store: .preview())
        .dynamicTypeSize(.accessibility5)
}
#endif
