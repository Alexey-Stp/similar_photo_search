import SwiftUI

/// Shown when photo access is blocked by parental controls or device management.
///
/// There is deliberately no Settings button: the user cannot change this setting themselves.
struct RestrictedAccessView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised")
                    .font(.system(.largeTitle))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("restricted.title", bundle: .module)
                    .font(.title.bold())
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
