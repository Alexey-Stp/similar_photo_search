import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shown when photo access is denied or restricted. Placeholder content until the permissions ticket.
struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

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
                #if canImport(UIKit)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("permissionDenied.openSettings", bundle: .module)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                #endif
            }
            .padding()
        }
    }
}
