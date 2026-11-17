import Domain
import SwiftUI

/// Floating bottom bar with the global Smart Select and Deselect actions and, with `onDelete`, Delete with the number
/// of selected photos as a badge, disabled while nothing is selected. It never deletes anything itself: `onDelete`
/// starts the deletion flow (SPS-25).
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

    /// A floating glass bar laid out like a tab bar: Smart Select, Deselect and, with `onDelete`, Delete with the
    /// count as a badge. Short labels only; VoiceOver reads the full summary ("38 photos, about 214 MB will be
    /// deleted") and the full delete title ("Delete 38 photos (214 MB)").
    public var body: some View {
        HStack(spacing: 0) {
            BarItem(titleKey: "selection.bar.smart", systemImage: "sparkles") {
                store.selectSmartAll()
            }
            .accessibilityLabel(Text("selection.smartSelectAll", bundle: .module))
            .accessibilityHint(Text("selection.smartSelectAll.hint", bundle: .module))
            BarItem(titleKey: "selection.bar.deselect", systemImage: "xmark.circle") {
                store.deselectAll()
            }
            .disabled(store.selectedCount == 0)
            .accessibilityLabel(Text("selection.deselectAll", bundle: .module))
            .accessibilityHint(Text("selection.deselectAll.hint", bundle: .module))
            if let onDelete {
                BarItem(
                    titleKey: "selection.delete.short",
                    systemImage: "trash.fill",
                    tint: .red,
                    badge: summary.photoCount,
                    action: onDelete
                )
                .disabled(summary.photoCount == 0)
                .accessibilityLabel(Text(Self.deleteTitle(for: summary)))
                .accessibilityHint(Text("selection.delete.hint", bundle: .module))
            }
        }
        .floatingBar()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(summary.text))
    }

    /// Apple's accessible red (#d70015), the Increase Contrast value of systemRed.
    static let deleteRed = Color(red: 215 / 255, green: 0, blue: 21 / 255)
}

extension View {
    /// The look of the floating bottom bars: glass, rounded, inset from the screen edges.
    func floatingBar() -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .glassBackground(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}

/// One item of a floating bar, like a tab bar item: an SF Symbol over a short label, an optional count badge on the
/// symbol. The icon carries the tint; the label stays `.primary`, so it reads on the glass.
struct BarItem: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var tint: Color = .primary
    var badge = 0
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge, format: .number)
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(SelectionSummaryBar.deleteRed, in: Capsule())
                                .offset(x: 14, y: -6)
                        }
                    }
                Text(titleKey, bundle: .module)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
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
