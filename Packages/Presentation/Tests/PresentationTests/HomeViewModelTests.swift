import Domain
import DomainTestSupport
import Foundation
import Presentation
import SwiftUI
import Testing

/// Idle timer and background tasks that do nothing.
@MainActor
private final class SilentLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    func setIdleTimerDisabled(_ disabled: Bool) {}

    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        nil
    }

    func endBackgroundTask(_ token: BackgroundTaskToken) {}
}

@MainActor
struct HomeViewModelTests {
    private struct Harness {
        let coordinator: MockScanCoordinator
        let repository: MockClusterRepository
        let observer: MockLibraryChangeObserver
        let home: HomeViewModel
    }

    private func makeHarness(stored: [StoredSessionResult] = []) -> Harness {
        let coordinator = MockScanCoordinator()
        let repository = MockClusterRepository(results: stored)
        let observer = MockLibraryChangeObserver()
        let lifecycle = SilentLifecycle()
        let scan = ScanViewModel(
            coordinator: coordinator,
            preferences: MockScopePreferencesStore(preferences: .default),
            selection: SelectionStore(sizes: MockAssetSizeEstimator()),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
        let home = HomeViewModel(scan: scan, results: repository, libraryChanges: observer)
        return Harness(coordinator: coordinator, repository: repository, observer: observer, home: home)
    }

    private func storedSession(
        _ newestID: String,
        at seconds: TimeInterval,
        clusters: [[String]]
    ) -> StoredSessionResult {
        StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: PhotoSession.id(newestID: newestID, newestDate: Date(timeIntervalSince1970: seconds)),
                content: SessionFingerprint.Content(memberCount: clusters.joined().count, digest: 1)
            ),
            clusters: clusters.map { SimilarityCluster(assetIDs: $0) },
            resultsKey: "key"
        )
    }

    private func selection(_ ids: [String]) -> ClusterSelection {
        ClusterSelection(
            cluster: SimilarityCluster(assetIDs: ids, suggestedKeeperID: ids.first),
            ranking: [],
            suggestedForDeletion: Set(ids.dropFirst()),
            needsReview: false
        )
    }

    /// Polls on the main actor until `condition` holds (up to 2 s).
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    private func startCount(_ harness: Harness) async -> Int {
        await harness.coordinator.startCalls.count
    }

    // MARK: - States

    @Test func neverScannedIsIdleAndLaunchDoesNotScan() async {
        let harness = makeHarness()
        await harness.home.launch()
        #expect(harness.home.viewState == .idle)
        #expect(await startCount(harness) == 0)
        #expect(!harness.home.hasPreviousScan)
    }

    @Test func aStartedScanShowsProgressAndTheLiveGroupCounter() async {
        let harness = makeHarness()
        await harness.home.startScan()
        let snapshot = ScanProgress(processed: 40, total: 100, phase: .analyzing)
        await harness.coordinator.send(snapshot)
        await harness.coordinator.send(.added([selection(["A1", "A2"]), selection(["B1", "B2"])]))
        #expect(await eventually { harness.home.viewState == .scanning(snapshot, foundSoFar: 2) })
        #expect(!harness.home.isRefreshing)
    }

    @Test func reviewNowOpensTheGroupListOnce() {
        let harness = makeHarness()
        harness.home.review()
        harness.home.review()
        #expect(harness.home.path == [.clusters])
    }

    @Test func compareOpensTheComparisonOfOneGroupOnce() {
        let harness = makeHarness()
        harness.home.review()
        harness.home.compare(clusterID: "A1")
        harness.home.compare(clusterID: "A1")
        #expect(harness.home.path == [.clusters, .comparison(clusterID: "A1")])
    }

    @Test func aFinishedScanWithGroupsShowsTheSummary() async {
        let harness = makeHarness()
        await harness.home.startScan()
        await harness.coordinator.send(.added([selection(["A1", "A2", "A3"]), selection(["B1", "B2"])]))
        await harness.coordinator.send(ScanProgress(processed: 5, total: 5, skipped: [.iCloudOnly: 3], phase: .done))
        await harness.coordinator.finish()
        #expect(await eventually { !harness.home.scan.isScanning })

        guard case .results(let summary) = harness.home.viewState else {
            Issue.record("Expected results, got \(harness.home.viewState)")
            return
        }
        #expect(summary.groupCount == 2)
        #expect(summary.photoCount == 5)
        #expect(summary.skipped.counts == [.iCloudOnly: 3])
        #expect(harness.home.hasPreviousScan)
    }

    @Test func aFinishedScanWithoutGroupsIsEmpty() async {
        let harness = makeHarness()
        await harness.home.startScan()
        await harness.coordinator.send(ScanProgress(processed: 5, total: 5, phase: .done))
        await harness.coordinator.finish()
        #expect(await eventually { harness.home.viewState == .empty })
    }

    @Test func aCancelledFirstScanWithoutGroupsIsIdleAgain() async {
        let harness = makeHarness()
        await harness.home.startScan()
        harness.home.scan.cancelScan()
        #expect(await eventually { !harness.home.scan.isScanning })
        #expect(harness.home.viewState == .idle)
    }

    @Test func aFailedScanIsAnErrorEvenWithGroups() async {
        let harness = makeHarness()
        await harness.home.startScan()
        await harness.coordinator.send(.added([selection(["A1", "A2"])]))
        await harness.coordinator.send(ScanProgress(phase: .failed(.missingThreshold(revision: 2))))
        await harness.coordinator.finish()
        #expect(await eventually {
            if case .error = harness.home.viewState { return true }
            return false
        })
        #expect(harness.home.summary.groupCount == 1, "The error card still offers the groups found")
    }

    // MARK: - Launch

    @Test func launchShowsStoredGroupsAtOnceAndRescansSilently() async {
        let harness = makeHarness(stored: [
            storedSession("old", at: 100, clusters: [["O1", "O2"]]),
            storedSession("new", at: 200, clusters: [["N1", "N2"]])
        ])
        await harness.home.launch()

        #expect(harness.home.scan.selection.clusterIDs == ["N1", "O1"], "Newest session first")
        #expect(harness.home.scan.selection.selectedCount == 0, "Nothing is pre-selected before the rescan")
        #expect(await startCount(harness) == 1)
        #expect(harness.home.isRefreshing)
        guard case .results(let summary) = harness.home.viewState else {
            Issue.record("Expected results during the silent rescan, got \(harness.home.viewState)")
            return
        }
        #expect(summary.groupCount == 2)
    }

    @Test func theRescanReplacesStoredGroupsInPlaceWithASuggestion() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        await harness.coordinator.send(.added([selection(["N1", "N2"])]))
        #expect(await eventually { harness.home.scan.selection.selectedCount == 1 })
        #expect(harness.home.scan.selection.clusterIDs == ["N1"])
    }

    @Test func storedSessionsWithoutGroupsLaunchIntoEmpty() async {
        let harness = makeHarness(stored: [storedSession("only", at: 100, clusters: [])])
        await harness.home.launch()
        #expect(harness.home.viewState == .empty)
        #expect(harness.home.isRefreshing)
    }

    @Test func launchRunsOnce() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        await harness.home.launch()
        #expect(await startCount(harness) == 1)
        #expect(harness.observer.changesCallCount == 1)
    }

    @Test func aScanStartedBeforeLaunchKeepsItsOwnGroups() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.startScan()
        await harness.home.launch()
        #expect(harness.home.scan.selection.clusterIDs.isEmpty, "The running scan publishes the groups itself")
        #expect(await startCount(harness) == 1)
    }

    // MARK: - Refresh

    @Test func pullToRefreshAfterAScanIsSilent() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        await harness.coordinator.send(ScanProgress(phase: .done))
        await harness.coordinator.finish()
        #expect(await eventually { !harness.home.scan.isScanning })

        await harness.home.refresh()
        #expect(await startCount(harness) == 2)
        #expect(harness.home.isRefreshing)
    }

    @Test func pullToRefreshBeforeAnyScanShowsTheFullScan() async {
        let harness = makeHarness()
        await harness.home.refresh()
        #expect(await startCount(harness) == 1)
        #expect(!harness.home.isRefreshing)
        #expect(await eventually {
            if case .scanning = harness.home.viewState { return true }
            return false
        })
    }

    @Test func pullToRefreshDuringAScanDoesNotRestartIt() async {
        let harness = makeHarness()
        await harness.home.startScan()
        await harness.home.refresh()
        #expect(await startCount(harness) == 1)
    }

    // MARK: - Library changes

    @Test func aLibraryChangeAfterAScanStartsASilentScan() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        await harness.coordinator.finish()
        #expect(await eventually { !harness.home.scan.isScanning })

        harness.observer.signal()
        #expect(await eventually { harness.home.scan.isScanning })
        #expect(await startCount(harness) == 2)
        #expect(harness.home.isRefreshing)
    }

    @Test func aLibraryChangeDuringAScanRescansAfterIt() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        harness.observer.signal()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await startCount(harness) == 1, "The running scan is not restarted")

        await harness.coordinator.finish()
        var started = 0
        for _ in 0..<500 where started < 2 {
            started = await startCount(harness)
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(started == 2)
    }

    @Test func aLibraryChangeInTheBackgroundRescansWhenActiveAgain() async {
        let harness = makeHarness(stored: [storedSession("new", at: 200, clusters: [["N1", "N2"]])])
        await harness.home.launch()
        await harness.coordinator.finish()
        #expect(await eventually { !harness.home.scan.isScanning })

        harness.home.scenePhaseChanged(to: .background)
        harness.observer.signal()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await startCount(harness) == 1)

        harness.home.scenePhaseChanged(to: .active)
        #expect(await eventually { harness.home.scan.isScanning })
        #expect(await startCount(harness) == 2)
    }

    @Test func aLibraryChangeBeforeAnyScanIsIgnored() async {
        let harness = makeHarness()
        await harness.home.launch()
        harness.observer.signal()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await startCount(harness) == 0)
    }
}
