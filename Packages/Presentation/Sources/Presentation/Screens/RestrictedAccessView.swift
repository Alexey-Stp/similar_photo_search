import SwiftUI

/// Shown when photo access is blocked by parental controls or device management.
///
/// There is deliberately no Settings button: the user cannot change this setting themselves.
struct RestrictedAccessView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeroSymbol(systemName: "hand.raised")
                Text("restricted.title", bundle: .module)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("restricted.message", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview("Light") {
    RestrictedAccessView()
}

#Preview("Dark") {
    RestrictedAccessView()
        .preferredColorScheme(.dark)
}
