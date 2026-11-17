import SwiftUI

/// An SF Symbol in a large circle in the label colour (black in Light, white in Dark), for the top of full-screen
/// messages: onboarding, photo access off or restricted. Grows with Dynamic Type up to a cap. Decorative.
struct HeroSymbol: View {
    let systemName: String
    /// A second symbol shown as a small badge on the circle, such as the airplane on "100% on your device".
    var badge: String?

    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 112

    var body: some View {
        let side = min(side, 168)
        Image(systemName: systemName)
            .font(.system(size: side * 0.42, weight: .semibold))
            .foregroundStyle(.background)
            .frame(width: side, height: side)
            .background(.primary, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: side * 0.18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: side * 0.38, height: side * 0.38)
                        .background(.tint, in: Circle())
                        .overlay(Circle().strokeBorder(.background, lineWidth: 4))
                }
            }
            .padding(.top, 32)
            .accessibilityHidden(true)
    }
}
