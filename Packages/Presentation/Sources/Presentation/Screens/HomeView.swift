import SwiftUI

/// Main screen. Placeholder content until the scan ticket.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("home.empty.title", bundle: .module)
                } icon: {
                    Image(systemName: "square.on.square")
                        .accessibilityHidden(true)
                }
            } description: {
                Text("home.empty.message", bundle: .module)
            }
            .navigationTitle(Text("home.title", bundle: .module))
        }
    }
}
