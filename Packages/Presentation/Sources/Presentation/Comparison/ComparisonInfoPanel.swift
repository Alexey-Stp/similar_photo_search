import SwiftUI

/// The focused photo's details (date, resolution, size, badges, why it ranks well) over a row of actions laid out
/// like a tab bar: Keep Only, Mark / Unmark for deletion, Best and Delete Now. Lives in the comparison's bottom
/// glass toolbar.
struct ComparisonInfoPanel: View {
    let viewModel: PhotoComparisonViewModel
    let assetID: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The facts above the action buttons.
    var body: some View {
        let info = viewModel.info(for: assetID)
        VStack(alignment: .leading, spacing: 8) {
            facts(info)
            badges(info)
            if !info.reasonTexts.isEmpty {
                Text(info.reasonTexts.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            actions
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The date, then resolution and file size on one line.
    private func facts(_ info: ComparisonPhotoInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let date = info.date {
                Text(ClusterCardModel.headerDateText(date))
                    .font(.headline)
            }
            let details = [info.resolutionText, info.fileSizeText ?? sizeUnavailable(info)].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Size unavailable" once the details are loaded without a size.
    private func sizeUnavailable(_ info: ComparisonPhotoInfo) -> String? {
        guard viewModel.infos[assetID] != nil else { return nil }
        return String(localized: "compare.info.sizeUnavailable", bundle: .module)
    }

    /// Best (solid green, as on the group card), the keep / delete status, Favorite, Edited and Live.
    private func badges(_ info: ComparisonPhotoInfo) -> some View {
        let selected = viewModel.isSelected(assetID)
        return FlowingBadges {
            if viewModel.isBest(assetID) {
                BestBadge(isInset: false)
            }
            badge(selected ? "compare.status.selected" : "compare.status.kept",
                  symbol: selected ? "trash" : "checkmark",
                  tint: selected ? .red : .gray)
            if info.isFavorite {
                badge("compare.badge.favorite", symbol: "heart.fill", tint: .pink)
            }
            if info.isEdited {
                badge("compare.badge.edited", symbol: "slider.horizontal.3", tint: .gray)
            }
            if info.isLivePhoto {
                badge("compare.badge.live", symbol: "livephoto", tint: .gray)
            }
        }
    }

    /// One tinted capsule with an icon and a short text.
    private func badge(_ key: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        Label {
            Text(key, bundle: .module)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.3), in: Capsule())
    }

    /// Keep Only, Mark / Unmark, Best and Delete Now as icon items with short labels; VoiceOver reads the full
    /// titles. At accessibility text sizes the items stack in two rows.
    private var actions: some View {
        let isMissing = viewModel.isMissing(assetID)
        let isSelected = viewModel.isSelected(assetID)
        let isBest = viewModel.isBest(assetID)
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 4) {
            BarItem(titleKey: "compare.tab.keepOnly", systemImage: "checkmark.circle") {
                viewModel.keepOnly(assetID)
            }
            .accessibilityLabel(Text("compare.action.keepOnly", bundle: .module))
            .accessibilityHint(Text("compare.action.keepOnly.hint", bundle: .module))
            BarItem(
                titleKey: isSelected ? "compare.tab.unmark" : "compare.tab.mark",
                systemImage: isSelected ? "arrow.uturn.backward" : "minus.circle"
            ) {
                viewModel.toggle(assetID)
            }
            .accessibilityLabel(Text(isSelected ? "compare.action.keep" : "compare.action.delete", bundle: .module))
            .sensoryFeedback(.selection, trigger: isSelected)
            BarItem(titleKey: "compare.tab.best", systemImage: isBest ? "star.fill" : "star", tint: .yellow) {
                viewModel.markAsBest(assetID)
            }
            .disabled(isBest)
            .accessibilityLabel(Text("compare.action.markBest", bundle: .module))
            BarItem(titleKey: "compare.tab.delete", systemImage: "trash.fill", tint: .red) {
                viewModel.deleteNow(assetID)
            }
            .accessibilityLabel(Text("compare.action.deleteNow", bundle: .module))
            .accessibilityHint(Text("compare.action.deleteNow.hint", bundle: .module))
        }
        .disabled(isMissing)
    }
}

/// Badges in a row that wraps onto more lines when they don't fit (large Dynamic Type).
private struct FlowingBadges<Content: View>: View {
    @ViewBuilder let content: Content

    /// The badges in one row, or one below the other when the row does not fit.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}
