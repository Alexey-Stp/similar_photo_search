import Domain
import SwiftUI

/// Main screen: the scan dashboard (`HomeDashboard`) built from the app session's `HomeViewModel`.
struct HomeView: View {
    let viewModel: PermissionViewModel
    @Environment(\.viewModelFactory) private var factory

    var body: some View {
        if let home = factory?.homeViewModel {
            HomeDashboard(home: home, permission: viewModel)
        } else {
            ProgressView()
        }
    }
}

/// The scan dashboard: one card for the current state (idle, scanning, results, empty, error), the skipped-photos
/// line, pull-to-refresh, the "Scan scope" toolbar button and, under limited access, a banner at the top.
struct HomeDashboard: View {
    @Bindable var home: HomeViewModel
    let permission: PermissionViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingScope = false
    @State private var isShowingSkipped = false

    var body: some View {
        NavigationStack(path: $home.path) {
            ScrollView {
                VStack(spacing: 16) {
                    if home.isRefreshing {
                        ScanProgressBar(scan: home.scan)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    stateCard
                    if home.viewState != .idle, let headline = home.summary.skipped.headline {
                        SkippedSummaryButton(headline: headline) { isShowingSkipped = true }
                    }
                }
                .padding()
            }
            .refreshable { await home.refresh() }
            .onAppear { home.scan.scanScreenAppeared() }
            .onDisappear { home.scan.scanScreenDisappeared() }
            .navigationTitle(Text("home.title", bundle: .module))
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .clusters:
                    ClusterListScreen(scan: home.scan)
                }
            }
            .toolbar { scopeButton }
            .sheet(isPresented: $isShowingScope) {
                ScopeSelectionSheet { isShowingScope = false }
            }
            .sheet(isPresented: $isShowingSkipped) {
                SkippedPhotosSheet(summary: home.summary.skipped) { isShowingSkipped = false }
            }
            .safeAreaInset(edge: .top) {
                if permission.isLimited, let count = permission.accessiblePhotoCount {
                    LimitedAccessBanner(
                        photoCount: count,
                        onManage: { Task { await permission.presentLimitedPicker() } },
                        onSettings: { permission.openSettings() }
                    )
                }
            }
        }
        .task { await home.launch() }
        .onChange(of: scenePhase) { _, phase in
            home.scenePhaseChanged(to: phase)
        }
    }

    @ViewBuilder private var stateCard: some View {
        switch home.viewState {
        case .idle:
            HomeIdleCard { Task { await home.startScan() } }
        case .scanning(_, let foundSoFar):
            HomeScanningCard(scan: home.scan, foundSoFar: foundSoFar) { home.review() }
        case .results(let summary):
            HomeResultsCard(summary: summary) { home.review() }
        case .empty:
            HomeEmptyCard { Task { await home.startScan() } }
        case .error(let message):
            HomeErrorCard(
                message: message,
                summary: home.summary,
                onRetry: { Task { await home.startScan() } },
                onReview: { home.review() }
            )
        }
    }

    private var scopeButton: some ToolbarContent {
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
}

#if DEBUG
#Preview("Idle") {
    HomeDashboard(home: .preview(selection: .empty()), permission: .preview(status: .authorized))
}

#Preview("Scanning, groups found") {
    let home = HomeViewModel.preview()
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
        .task { await home.startScan() }
}

#Preview("Scanning, paused, dark") {
    let home = HomeViewModel.preview(
        snapshot: ScanProgress(
            processed: 800,
            total: 10_000,
            phase: .throttled,
            conditions: ScanConditions(thermalLevel: .critical)
        ),
        selection: .empty()
    )
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
        .preferredColorScheme(.dark)
        .task { await home.startScan() }
}

#Preview("Results, refreshing") {
    let home = HomeViewModel.preview(stored: true)
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
}

#Preview("Results, AX5") {
    let home = HomeViewModel.preview(snapshot: .previewDone(skipped: [.iCloudOnly: 128]))
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
        .dynamicTypeSize(.accessibility5)
        .task { await home.startScan() }
}

#Preview("Empty") {
    let home = HomeViewModel.preview(
        snapshot: .previewDone(skipped: [.iCloudOnly: 12, .noDate: 2]),
        selection: .empty()
    )
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
        .task { await home.startScan() }
}

#Preview("Error, dark") {
    let home = HomeViewModel.preview(snapshot: ScanProgress(phase: .failed(.missingThreshold(revision: 2))))
    return HomeDashboard(home: home, permission: .preview(status: .authorized))
        .preferredColorScheme(.dark)
        .task { await home.startScan() }
}

#Preview("Limited access") {
    let permission = PermissionViewModel.preview(status: .limited, photoCount: 42)
    return HomeDashboard(home: .preview(selection: .empty()), permission: permission)
        .task { await permission.refresh() }
}
#endif
