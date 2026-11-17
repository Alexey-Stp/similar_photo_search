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

/// The scan dashboard: one card for the current state (idle, scanning, results, empty, error), the groups found
/// listed below it, the skipped-photos line, pull-to-refresh, the "Scan scope" toolbar button and, under limited
/// access, a banner at the top.
struct HomeDashboard: View {
    @Bindable var home: HomeViewModel
    let permission: PermissionViewModel
    @Environment(\.viewModelFactory) private var factory
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingScope = false
    @State private var isShowingSkipped = false

    var body: some View {
        NavigationStack(path: $home.path) {
            ScrollView {
                VStack(spacing: 16) {
                    stateCard
                    if home.viewState != .idle, let headline = home.summary.skipped.headline {
                        SkippedSummaryButton(headline: headline) { isShowingSkipped = true }
                    }
                    if let list = factory?.clusterListViewModel, !list.rows.isEmpty {
                        HomeGroupsSection(
                            list: list,
                            onOpen: { home.openGroup($0) },
                            onSeeAll: { home.review() }
                        )
                        .padding(.top, 8)
                    }
                    if home.viewState != .idle {
                        HomePrivacyFooter()
                    }
                }
                .padding()
            }
            .modifier(HomeGroupDialogs(home: home, list: factory?.clusterListViewModel))
            .onChange(of: home.scan.clusterRevision, initial: true) {
                // Dates and sizes of the groups load even while no row is listed (an empty filter).
                factory?.clusterListViewModel.clustersChanged()
            }
            .refreshable { await home.refresh() }
            .onAppear { home.scan.scanScreenAppeared() }
            .onDisappear { home.scan.scanScreenDisappeared() }
            .navigationTitle(isScanningInFull ? Text(verbatim: "") : Text("home.title", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(isScanningInFull ? .inline : .automatic)
            #endif
            .navigationDestination(for: HomeRoute.self, destination: destination)
            .toolbar { moreMenu }
            .sheet(isPresented: $isShowingScope) {
                ScopeSelectionSheet { isShowingScope = false }
            }
            .sheet(isPresented: $isShowingSkipped) {
                SkippedPhotosSheet(summary: home.summary.skipped) { isShowingSkipped = false }
            }
            .fullScreenCover(item: $home.comparison) { request in
                PhotoComparisonHost(clusterID: request.clusterID)
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

    /// The screens pushed from Home; they share the app session's group list.
    @ViewBuilder private func destination(_ route: HomeRoute) -> some View {
        if let list = factory?.clusterListViewModel {
            switch route {
            case .clusters:
                ClusterListScreen(
                    viewModel: list,
                    onOpen: { home.openGroup($0) },
                    onCompare: { home.compare(clusterID: $0) },
                    isDialogActive: home.path.last == route && home.comparison == nil
                )
            case .group(let clusterID):
                ClusterGroupScreen(
                    viewModel: list,
                    clusterID: clusterID,
                    isDialogActive: home.path.last == route && home.comparison == nil
                ) { home.compare(clusterID: $0) }
            }
        }
    }

    @ViewBuilder private var stateCard: some View {
        switch home.viewState {
        case .idle:
            HomeIdleCard { Task { await home.startScan() } }
        case .scanning(_, let foundSoFar):
            HomeScanningCard(scan: home.scan, foundSoFar: foundSoFar) { home.review() }
        case .results(let summary):
            HomeResultsCard(
                summary: summary,
                sizes: factory?.clusterListViewModel.allGroupsSizes,
                scannedCount: home.scan.progress?.total,
                refreshText: refreshText,
                onReview: { home.review() }
            )
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

    /// Whether the full scanning state is shown (the large title is hidden then, the ring says it all).
    private var isScanningInFull: Bool {
        if case .scanning = home.viewState { return true }
        return false
    }

    /// "Checking for new photos… 42 %" while a silent refresh runs.
    private var refreshText: String? {
        guard home.isRefreshing else { return nil }
        return String(localized: "home.refreshing \(home.scan.percentText)", bundle: .module)
    }

    /// One "…" menu in the navigation bar: Scan Scope and, after a scan, Start Over (asks first), away from Review.
    private var moreMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isShowingScope = true
                } label: {
                    Label {
                        Text("home.scope", bundle: .module)
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                if home.hasPreviousScan, !home.scan.isScanning {
                    Divider()
                    Button(role: .destructive) {
                        home.isConfirmingStartOver = true
                    } label: {
                        Label {
                            Text("home.startOver", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            } label: {
                Label {
                    Text("home.more", bundle: .module)
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .accessibilityHint(Text("home.more.hint", bundle: .module))
        }
    }
}

/// Home's dialogs: "Start over?" and, while Home is on top, "Delete every photo of this group?" for the groups
/// listed on it.
private struct HomeGroupDialogs: ViewModifier {
    @Bindable var home: HomeViewModel
    let list: ClusterListViewModel?

    func body(content: Content) -> some View {
        Group {
            if let list {
                content.deleteAllConfirmation(list, isActive: home.path.isEmpty && home.comparison == nil)
            } else {
                content
            }
        }
        .alert(
            Text("home.startOver.failed.title", bundle: .module),
            isPresented: $home.didStartOverFail
        ) {
            Button {
                Task { await home.startOver() }
            } label: {
                Text("home.retry", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("deletion.review.cancel", bundle: .module)
            }
        } message: {
            Text("home.startOver.failed.message", bundle: .module)
        }
        .confirmationDialog(
            Text("home.startOver.title", bundle: .module),
            isPresented: $home.isConfirmingStartOver,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await home.startOver() }
            } label: {
                Text("home.startOver.confirm", bundle: .module)
            }
        } message: {
            Text("home.startOver.message", bundle: .module)
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
