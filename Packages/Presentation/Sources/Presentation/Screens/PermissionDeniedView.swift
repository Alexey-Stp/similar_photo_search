import SwiftUI

/// Shown when the user denied photo access. Offers a shortcut to the app's page in Settings.
struct PermissionDeniedView: View {
    let viewModel: PermissionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(.largeTitle))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("permissionDenied.title", bundle: .module)
                    .font(.title.bold())
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
