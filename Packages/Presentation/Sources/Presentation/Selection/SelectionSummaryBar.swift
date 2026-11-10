import Domain
import SwiftUI

/// Bottom bar with the global "Smart Select All" and "Deselect All" actions and what would be deleted right now
/// ("38 photos, about 214 MB will be deleted"). It never deletes anything itself; the delete button comes with SPS-25.
///
/// Reads only the store's totals, so toggling a photo re-renders this bar and that photo's cluster, nothing else.
public struct SelectionSummaryBar: View {
    private let store: SelectionStore

    /// Creates the bar for a store.
    public init(store: SelectionStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.summary.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
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
    SelectionSummaryBar(store: .preview())
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
