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

    /// "Keep This One" as the ink pill, then Mark for Deletion / Keep, Mark as Best and Delete Now as round icon
    /// buttons (their titles are the VoiceOver labels). At accessibility text sizes they stack and show their
    /// titles.
    private var actions: some View {
        let isMissing = viewModel.isMissing(assetID)
        let isSelected = viewModel.isSelected(assetID)
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let layout = isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button {
                viewModel.keepOnly(assetID)
            } label: {
                Label {
                    Text("compare.action.keepOnly", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark")
                }
            }
            .buttonStyle(HomeInkButtonStyle())
            .accessibilityHint(Text("compare.action.keepOnly.hint", bundle: .module))
            Button(role: isSelected ? nil : .destructive) {
                viewModel.toggle(assetID)
            } label: {
                Label {
                    let key: LocalizedStringKey = isSelected ? "compare.action.keep" : "compare.action.delete"
                    Text(key, bundle: .module)
                } icon: {
                    Image(systemName: isSelected ? "arrow.uturn.backward" : "checkmark.circle")
                }
            }
            .buttonStyle(PanelRoundButtonStyle(tint: isSelected ? .primary : Self.deleteTint, showsTitle: isLarge))
            .sensoryFeedback(.selection, trigger: isSelected)
            Button {
                viewModel.markAsBest(assetID)
            } label: {
                Label {
                    Text("compare.action.markBest", bundle: .module)
                } icon: {
                    Image(systemName: viewModel.isBest(assetID) ? "star.fill" : "star")
                }
            }
            .buttonStyle(PanelRoundButtonStyle(tint: .yellow, showsTitle: isLarge))
            .disabled(viewModel.isBest(assetID))
            Button(role: .destructive) {
                viewModel.deleteNow(assetID)
            } label: {
                Label {
                    Text("compare.action.deleteNow", bundle: .module)
                } icon: {
                    Image(systemName: "trash.fill")
                }
            }
            .buttonStyle(PanelRoundButtonStyle(
                tint: .white,
                fill: SelectionSummaryBar.deleteRed,
                showsTitle: isLarge
            ))
            .accessibilityHint(Text("compare.action.deleteNow.hint", bundle: .module))
        }
        .disabled(isMissing)
    }

    /// Apple's dark-mode accessible red (#ff6961): the trash icon on the panel's grey fill.
    static let deleteTint = Color(red: 1, green: 105 / 255, blue: 97 / 255)
}

/// A 50-point round button on the panel's grey fill with a tinted icon; a pill with the title at accessibility
/// text sizes.
private struct PanelRoundButtonStyle: ButtonStyle {
    let tint: Color
    var fill = Color(white: 0.2)
    let showsTitle: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if showsTitle {
                configuration.label.labelStyle(.titleAndIcon)
            } else {
                configuration.label.labelStyle(.iconOnly)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, showsTitle ? 18 : 0)
        .frame(minWidth: 50, minHeight: 50)
        .background(fill, in: Capsule())
        .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
        .contentShape(Capsule())
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
