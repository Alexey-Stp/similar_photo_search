import SwiftUI

/// The Home look: an "ink" pill for the one primary action of a card (label colour on the background colour, so it
/// passes contrast in every appearance), rounded hero figures and stat tiles.
struct HomeInkButtonStyle: ButtonStyle {
    /// The label in a full-width pill.
    func makeBody(configuration: Configuration) -> some View {
        HomeInkLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

/// The pill a `HomeInkButtonStyle` draws; a view of its own so its height scales with Dynamic Type.
private struct HomeInkLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.background)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(.primary, in: RoundedRectangle(cornerRadius: minHeight / 2, style: .continuous))
            .opacity(isEnabled ? (isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// A large rounded figure, such as the reclaimable size "214 MB". Scales with Dynamic Type.
struct HomeHeroNumber: View {
    let text: String

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// A small tile with a rounded figure over its caption, such as "12" over "Groups" or "1.4 GB" over "Total Size".
struct HomeStatTile: View {
    let text: String
    let titleKey: LocalizedStringKey

    /// A tile with a count.
    init(value: Int, titleKey: LocalizedStringKey) {
        self.init(text: value.formatted(.number), titleKey: titleKey)
    }

    /// A tile with a formatted figure, such as a size.
    init(text: String, titleKey: LocalizedStringKey) {
        self.text = text
        self.titleKey = titleKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            Text(titleKey, bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A storage-style bar of the photos in groups, like Settings › iPhone Storage: the share selected for deletion in
/// red, the rest (kept) in grey, with a one-line legend. A neutral track and "Calculating sizes…" while sizes load,
/// "Sizes unavailable" once they were looked up but none is known, at the same height, so the card doesn't move.
/// When some sizes are unavailable the legend says "at least".
struct StorageBar: View {
    let sizes: GroupSizes?

    var body: some View {
        let known = sizes.flatMap { $0.isComplete && $0.totalBytes > 0 ? $0 : nil }
        let share = known.map { min(1, Double($0.selectedBytes) / Double($0.totalBytes)) } ?? 0
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: share > 0 && share < 1 ? 2 : 0) {
                    Rectangle()
                        .fill(.red)
                        .frame(width: proxy.size.width * share)
                    Rectangle()
                        .fill(known == nil ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.gray))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.25), value: share)
            .accessibilityHidden(true)
            legend(known)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func legend(_ known: GroupSizes?) -> some View {
        if let known {
            let toDelete = ClusterCardView.format(known.selectedBytes)
            let kept = ClusterCardView.format(known.totalBytes - known.selectedBytes)
            HStack(spacing: 16) {
                if known.unavailableCount > 0 {
                    item(.red, Text("home.storage.toDelete.atLeast \(toDelete)", bundle: .module))
                    item(.gray, Text("home.storage.kept.atLeast \(kept)", bundle: .module))
                } else {
                    item(.red, Text("home.storage.toDelete \(toDelete)", bundle: .module))
                    item(.gray, Text("home.storage.kept \(kept)", bundle: .module))
                }
            }
        } else if let sizes, sizes.isComplete {
            Text("home.storage.unavailable", bundle: .module)
        } else {
            Text("home.storage.calculating", bundle: .module)
        }
    }

    private func item(_ color: Color, _ text: Text) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            text
        }
    }
}

/// "Everything happens on this iPhone." with a lock, under the Home card.
struct HomePrivacyFooter: View {
    var body: some View {
        Label {
            Text("home.privacy.footer", bundle: .module)
        } icon: {
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

#if DEBUG
#Preview("Ink button, stat tiles") {
    VStack(spacing: 16) {
        HomeHeroNumber(text: "1.2 GB")
        HStack(spacing: 8) {
            HomeStatTile(value: 12, titleKey: "home.stat.groups")
            HomeStatTile(value: 87, titleKey: "home.stat.photos")
        }
        Button("Review") {}
            .buttonStyle(HomeInkButtonStyle())
        HomePrivacyFooter()
    }
    .padding()
}

#Preview("Dark, AX5") {
    VStack(spacing: 16) {
        HomeHeroNumber(text: "214 MB")
        HomeStatTile(value: 12, titleKey: "home.stat.groups")
        Button("Review Now") {}
            .buttonStyle(HomeInkButtonStyle())
    }
    .padding()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
#endif
