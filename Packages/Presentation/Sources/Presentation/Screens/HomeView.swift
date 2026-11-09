import SwiftUI

/// Main screen. Placeholder content until the scan ticket.
/// Under limited access a persistent banner sits at the top.
/// The toolbar's "Scan scope" button opens the scope sheet.
struct HomeView: View {
    let viewModel: PermissionViewModel
    @State private var isShowingScope = false

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingScope = true
                    } label: {
                        Label {
                            Text("home.scope", bundle: .module)
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                    .accessibilityHint(Text("home.scope.hint", bundle: .module))
                }
            }
            .sheet(isPresented: $isShowingScope) {
                ScopeSelectionSheet { isShowingScope = false }
            }
            .safeAreaInset(edge: .top) {
                if viewModel.isLimited, let count = viewModel.accessiblePhotoCount {
                    LimitedAccessBanner(
                        photoCount: count,
                        onManage: { Task { await viewModel.presentLimitedPicker() } },
                        onSettings: { viewModel.openSettings() }
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview("Limited access") {
    let viewModel = PermissionViewModel.preview(status: .limited, photoCount: 42)
    return HomeView(viewModel: viewModel)
        .task { await viewModel.refresh() }
}
#endif
