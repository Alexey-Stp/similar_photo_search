import SwiftUI

/// The "Best" badge on the suggested keeper: a star and "Best" in black on a green capsule. White on systemGreen
/// is only about 2:1; black is over 9:1 in both appearances.
struct BestBadge: View {
    /// Whether the badge sits inset on a photo (the group card) rather than in a row of badges.
    var isInset = true

    var body: some View {
        Label {
            Text("clusters.badge.best", bundle: .module)
        } icon: {
            Image(systemName: "star.fill")
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(.black)
        .background(.green, in: Capsule())
        .padding(isInset ? 8 : 0)
        .accessibilityHidden(isInset)
    }
}

/// The red checkmark on a photo selected for deletion, ringed in white so it reads on any photo.
struct SelectionCheck: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
            .font(.title2)
            .background(Circle().fill(.white).padding(1))
            .padding(6)
            .accessibilityHidden(true)
    }
}

/// A small label in the card footer: a tinted icon and the word in `.primary` on a quiet capsule. Orange and blue
/// text on the card fall below 4.5:1 in Light mode, so only the icon carries the tint.
struct ClusterChip: View {
    let text: Text
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            text
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .labelStyle(CompactLabelStyle())
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: Capsule())
    }
}

/// Icon and title with a tight gap, for badges and chips.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
