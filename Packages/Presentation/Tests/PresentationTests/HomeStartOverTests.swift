import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// Idle timer and background tasks that do nothing.
@MainActor
private final class QuietLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    func setIdleTimerDisabled(_ disabled: Bool) {}

    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        nil
    }

    func endBackgroundTask(_ token: BackgroundTaskToken) {}
}

/// "Start Over" on Home: forgets stored groups and choices, then scans again.
@MainActor
struct HomeStartOverTests {
    @Test func startOverForgetsStoredGroupsAndChoicesAndScansAgain() async {
        let coordinator = MockScanCoordinator()
        let stored = StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: PhotoSession.id(newestID: "N1", newestDate: Date(timeIntervalSince1970: 200)),
                content: SessionFingerprint.Content(memberCount: 2, digest: 1)
            ),
            clusters: [SimilarityCluster(assetIDs: ["N1", "N2"])],
            resultsKey: "key"
        )
        let repository = MockClusterRepository(results: [stored])
        let lifecycle = QuietLifecycle()
        let scan = ScanViewModel(
            coordinator: coordinator,
            preferences: MockScopePreferencesStore(preferences: .default),
            selection: SelectionStore(sizes: MockAssetSizeEstimator()),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
        let home = HomeViewModel(scan: scan, results: repository, libraryChanges: MockLibraryChangeObserver())
        await home.launch()
        #expect(scan.selection.clusterIDs == ["N1"])

        await home.startOver()

        #expect(await repository.results.isEmpty, "Stored results are removed")
        #expect(scan.selection.clusterIDs.isEmpty)
        #expect(scan.selection.selectedCount == 0)
        #expect(await coordinator.startCalls.count == 2, "A new scan starts")
        #expect(!home.isRefreshing, "With the full scanning state")
    }
}
