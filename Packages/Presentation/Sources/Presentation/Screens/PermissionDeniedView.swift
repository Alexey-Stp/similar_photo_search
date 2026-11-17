import SwiftUI

/// Shown when the user denied photo access. Offers a shortcut to the app's page in Settings.
struct PermissionDeniedView: View {
    let viewModel: PermissionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeroSymbol(systemName: "lock.shield")
                Text("permissionDenied.title", bundle: .module)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("permissionDenied.message", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.openSettings()
                } label: {
                    Text("permissionDenied.openSettings", bundle: .module)
                }
                .buttonStyle(HomeInkButtonStyle())
                .accessibilityHint(Text("permissionDenied.openSettings.hint", bundle: .module))
            }
            .padding()
        }
    }
}

#if DEBUG
#Preview("Light") {
    PermissionDeniedView(viewModel: .preview(status: .denied))
}

#Preview("Dark") {
    PermissionDeniedView(viewModel: .preview(status: .denied))
        .preferredColorScheme(.dark)
}
#endif
