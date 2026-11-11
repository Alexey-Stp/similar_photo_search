import SwiftUI

/// Facts about the focused photo (date, resolution, size, badges, why it ranks well) and the actions on it:
/// "Keep This One", Delete / Keep, and "Mark as Best".
struct ComparisonInfoPanel: View {
    let viewModel: PhotoComparisonViewModel
    let assetID: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The facts above the action buttons.
    var body: some View {
        let info = viewModel.info(for: assetID)
        VStack(alignment: .leading, spacing: 10) {
            facts(info)
            badges(info)
            if !info.reasonTexts.isEmpty {
                Text(info.reasonTexts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            actions
        }
        .padding()
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

    /// Best, the keep / delete status, Favorite, Edited and Live.
    private func badges(_ info: ComparisonPhotoInfo) -> some View {
        let selected = viewModel.isSelected(assetID)
        return FlowingBadges {
            if viewModel.isBest(assetID) {
                badge("clusters.badge.best", symbol: "star.fill", tint: .green)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.3), in: Capsule())
    }

    private var actions: some View {
        let isMissing = viewModel.isMissing(assetID)
        let isSelected = viewModel.isSelected(assetID)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button {
                viewModel.keepOnly(assetID)
            } label: {
                Label {
                    Text("compare.action.keepOnly", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            .accessibilityHint(Text("compare.action.keepOnly.hint", bundle: .module))
            Button(role: isSelected ? nil : .destructive) {
                viewModel.toggle(assetID)
            } label: {
                Label {
                    let key: LocalizedStringKey = isSelected ? "compare.action.keep" : "compare.action.delete"
                    Text(key, bundle: .module)
                } icon: {
                    Image(systemName: isSelected ? "arrow.uturn.backward" : "trash")
                }
            }
            .sensoryFeedback(.selection, trigger: isSelected)
            Button {
                viewModel.markAsBest(assetID)
            } label: {
                Label {
                    Text("compare.action.markBest", bundle: .module)
                } icon: {
                    Image(systemName: "star")
                }
            }
            .disabled(viewModel.isBest(assetID))
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
