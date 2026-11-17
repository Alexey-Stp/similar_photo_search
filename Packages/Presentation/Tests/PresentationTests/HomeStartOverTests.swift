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

private struct WriteFailed: Error {}

/// "Start Over" on Home: forgets stored groups and choices, then scans again.
@MainActor
struct HomeStartOverTests {
    private struct Harness {
        let coordinator: MockScanCoordinator
        let repository: MockClusterRepository
        let scan: ScanViewModel
        let home: HomeViewModel
    }

    /// Home launched over one stored group, N1 + N2, with N2 selected for deletion.
    private func launchedWithAChoice() async -> Harness {
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
        scan.selection.toggle("N2", in: "N1")
        return Harness(coordinator: coordinator, repository: repository, scan: scan, home: home)
    }

    @Test func startOverForgetsStoredGroupsAndChoicesAndScansAgain() async {
        let harness = await launchedWithAChoice()
        #expect(harness.scan.selection.clusterIDs == ["N1"])
        #expect(harness.scan.selection.selectedCount > 0, "A choice exists before Start Over")

        await harness.home.startOver()

        #expect(await harness.repository.results.isEmpty, "Stored results are removed")
        #expect(harness.scan.selection.clusterIDs.isEmpty)
        #expect(harness.scan.selection.selectedCount == 0, "The choice is cleared")
        #expect(await harness.coordinator.startCalls.count == 2, "A new scan starts")
        #expect(!harness.home.isRefreshing, "With the full scanning state")
        #expect(!harness.home.didStartOverFail)
    }

    @Test func aFailedResetChangesNothingAndOffersARetry() async {
        let harness = await launchedWithAChoice()
        await harness.repository.setWriteError(WriteFailed())

        await harness.home.startOver()

        #expect(harness.home.didStartOverFail)
        #expect(await !harness.repository.results.isEmpty, "Stored results stay")
        #expect(harness.scan.selection.clusterIDs == ["N1"], "The groups stay")
        #expect(harness.scan.selection.selectedCount == 1, "The choice stays")
        #expect(await harness.coordinator.startCalls.count == 1, "No new scan")
    }

    @Test func sizesOfPhotosThatAreNotSelectedCanBeEstimated() async {
        let estimator = MockAssetSizeEstimator(sizes: ["A": 3_000, "B": 5_000])
        let store = SelectionStore(sizes: estimator)
        store.upsert([
            ClusterSelection(
                cluster: SimilarityCluster(assetIDs: ["A", "B"], suggestedKeeperID: "A"),
                ranking: [],
                suggestedForDeletion: [],
                needsReview: false
            )
        ])
        #expect(store.selectedCount == 0)

        store.estimateSizes(of: ["A"])
        for _ in 0..<500 where store.extraSizesRevision == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }

        #expect(store.extraSizesRevision == 1)
        #expect(store.selectedCount == 0, "Estimating selects nothing")
        #expect(store.summary.photoCount == 0, "The selection's summary is unchanged")
    }
}
