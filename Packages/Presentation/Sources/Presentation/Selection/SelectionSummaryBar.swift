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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// The summary, the bulk actions and, with `onDelete`, the delete button, in a floating glass bar. At
    /// accessibility text sizes the actions move under the summary.
    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(summary.text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: 8) {
                buttons
                deleteButton
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var buttons: some View {
        Button {
            store.selectSmartAll()
        } label: {
            Label {
                Text("selection.smartSelectAll", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(BarIconButtonStyle())
        .accessibilityHint(Text("selection.smartSelectAll.hint", bundle: .module))
        Button {
            store.deselectAll()
        } label: {
            Label {
                Text("selection.deselectAll", bundle: .module)
            } icon: {
                Image(systemName: "xmark")
            }
        }
        .buttonStyle(BarIconButtonStyle())
        .disabled(store.selectedCount == 0)
        .accessibilityHint(Text("selection.deselectAll.hint", bundle: .module))
    }

    /// "Delete" with a trash icon on Apple's accessible red (white text 5.4:1); VoiceOver reads the full title,
    /// "Delete 38 photos (214 MB)".
    @ViewBuilder private var deleteButton: some View {
        if let onDelete {
            Button(role: .destructive, action: onDelete) {
                Label {
                    Text("selection.delete.short", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(Self.deleteRed, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(summary.photoCount == 0 ? 0.4 : 1)
            .disabled(summary.photoCount == 0)
            .accessibilityLabel(Text(Self.deleteTitle(for: summary)))
            .accessibilityHint(Text("selection.delete.hint", bundle: .module))
        }
    }

    /// Apple's accessible red (#d70015), the Increase Contrast value of systemRed.
    static let deleteRed = Color(red: 215 / 255, green: 0, blue: 21 / 255)
}

/// A 48-point circle with an SF Symbol; the label's title is the VoiceOver label.
private struct BarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BarIconLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct BarIconLabel<Content: View>: View {
    let label: Content
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(.fill.secondary, in: Circle())
            .opacity(isEnabled ? (isPressed ? 0.6 : 1) : 0.35)
            .contentShape(Circle())
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
