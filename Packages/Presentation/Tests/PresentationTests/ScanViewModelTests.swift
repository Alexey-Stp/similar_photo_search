import Domain
import DomainTestSupport
import Foundation
import Presentation
import SwiftUI
import Testing

/// Records idle-timer and background-task calls; the expiration handler can be fired by hand.
@MainActor
private final class FakeLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    var idleTimerDisabled = false
    var idleTimerCalls: [Bool] = []
    var grantsTime = true
    var begun: [BackgroundTaskToken] = []
    var ended: [BackgroundTaskToken] = []
    var expiration: (@MainActor () -> Void)?

    func setIdleTimerDisabled(_ disabled: Bool) {
        idleTimerDisabled = disabled
        idleTimerCalls.append(disabled)
    }

    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        guard grantsTime else { return nil }
        let token = BackgroundTaskToken(rawValue: begun.count + 1)
        begun.append(token)
        self.expiration = expiration
        return token
    }

    func endBackgroundTask(_ token: BackgroundTaskToken) {
        ended.append(token)
    }
}

@MainActor
struct ScanViewModelTests {
    private struct Harness {
        let coordinator: MockScanCoordinator
        let preferences: MockScopePreferencesStore
        let lifecycle: FakeLifecycle
        let viewModel: ScanViewModel
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeHarness(preferences: ScopePreferences = .default) -> Harness {
        let coordinator = MockScanCoordinator()
        let store = MockScopePreferencesStore(preferences: preferences)
        let lifecycle = FakeLifecycle()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let viewModel = ScanViewModel(
            coordinator: coordinator,
            preferences: store,
            selection: SelectionStore(sizes: MockAssetSizeEstimator()),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle,
            now: { Self.now },
            calendar: calendar
        )
        return Harness(coordinator: coordinator, preferences: store, lifecycle: lifecycle, viewModel: viewModel)
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

    @Test func hasStartedScanSeparatesNeverScannedFromRunningAndFinished() async {
        let harness = makeHarness()
        #expect(!harness.viewModel.hasStartedScan)
        await harness.viewModel.startScan()
        #expect(harness.viewModel.hasStartedScan)
        await harness.coordinator.finish()
        #expect(await eventually { !harness.viewModel.isScanning })
        #expect(harness.viewModel.hasStartedScan, "A finished scan with no groups is not \"never scanned\"")
    }

    @Test func startUsesTheSavedScopeAndSessionGap() async throws {
        let saved = ScopePreferences(dateFilter: .last30Days, excludeScreenshots: false, sessionGap: .relaxed)
        let harness = makeHarness(preferences: saved)
        await harness.viewModel.startScan()

        let call = try #require(await harness.coordinator.startCalls.first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        #expect(call.scope == saved.scanScope(now: Self.now, calendar: calendar))
        #expect(call.sessionConfig == saved.sessionConfig)
        #expect(harness.viewModel.isScanning)
    }

    @Test func groupsAreAppendedInPublishingOrderAndRemoved() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        await harness.coordinator.send(.added([selection(["C1", "C2"])]))
        await harness.coordinator.send(.added([selection(["B1", "B2"]), selection(["A1", "A2"])]))
        #expect(await eventually { harness.viewModel.groupCount == 3 })
        #expect(harness.viewModel.selection.clusterIDs == ["C1", "B1", "A1"])

        await harness.coordinator.send(.removed(["B1"]))
        #expect(await eventually { harness.viewModel.groupCount == 2 })
        #expect(harness.viewModel.selection.clusterIDs == ["C1", "A1"])
    }

    @Test func progressIsShownAndTheEndStopsScanning() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        await harness.coordinator.send(ScanProgress(processed: 25, total: 100, phase: .analyzing, eta: 90))
        #expect(await eventually { harness.viewModel.progress?.processed == 25 })
        #expect(harness.viewModel.progress?.fractionCompleted == 0.25)
        #expect(harness.viewModel.etaText != nil)

        await harness.coordinator.send(ScanProgress(processed: 100, total: 100, phase: .done, eta: 0))
        await harness.coordinator.finish()
        #expect(await eventually { !harness.viewModel.isScanning })
        #expect(harness.viewModel.etaText == nil)
    }

    @Test func cancelAsksTheCoordinatorAndEndsTheScan() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        harness.viewModel.cancelScan()
        #expect(await eventually {
            !harness.viewModel.isScanning && harness.viewModel.progress?.phase == .cancelled
        })
        #expect(await harness.coordinator.cancelCallCount == 1)
    }

    @Test func thermalAndLowPowerNoticesFollowTheConditions() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        let hot = ScanConditions(thermalLevel: .critical)
        await harness.coordinator.send(ScanProgress(phase: .throttled, conditions: hot))
        #expect(await eventually { harness.viewModel.isPausedToCoolDown })
        #expect(!harness.viewModel.isSlowedByLowPowerMode)

        let lowPower = ScanConditions(isLowPowerModeEnabled: true)
        await harness.coordinator.send(ScanProgress(phase: .analyzing, conditions: lowPower))
        #expect(await eventually { harness.viewModel.isSlowedByLowPowerMode })
        #expect(!harness.viewModel.isPausedToCoolDown)
    }

    @Test func aFailedScanHasAnErrorText() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        await harness.coordinator.send(ScanProgress(phase: .failed(.missingThreshold(revision: 2))))
        await harness.coordinator.finish()
        #expect(await eventually { !harness.viewModel.isScanning && harness.viewModel.errorText != nil })
    }

    // MARK: - Lifecycle

    /// The screen stays awake only while the scan screen is visible and a scan runs.
    @Test func idleTimerIsDisabledOnlyWhileVisibleAndScanning() async {
        let harness = makeHarness()
        harness.viewModel.scanScreenAppeared()
        #expect(!harness.lifecycle.idleTimerDisabled)

        await harness.viewModel.startScan()
        #expect(harness.lifecycle.idleTimerDisabled)

        harness.viewModel.scanScreenDisappeared()
        #expect(!harness.lifecycle.idleTimerDisabled)
        harness.viewModel.scanScreenAppeared()
        #expect(harness.lifecycle.idleTimerDisabled)

        await harness.coordinator.finish()
        #expect(await eventually { !harness.lifecycle.idleTimerDisabled })
    }

    @Test func backgroundTimeIsRequestedOnlyDuringAScanAndGivenBack() async {
        let harness = makeHarness()
        harness.viewModel.scenePhaseChanged(to: .background)
        #expect(harness.lifecycle.begun.isEmpty, "No scan, no background task")
        harness.viewModel.scenePhaseChanged(to: .active)

        await harness.viewModel.startScan()
        harness.viewModel.scenePhaseChanged(to: .background)
        #expect(harness.lifecycle.begun.count == 1)
        harness.viewModel.scenePhaseChanged(to: .active)
        #expect(harness.lifecycle.ended == harness.lifecycle.begun)

        harness.viewModel.scenePhaseChanged(to: .background)
        await harness.coordinator.finish()
        #expect(await eventually { harness.lifecycle.ended.count == 2 }, "The scan's end gives the time back")
    }

    @Test func expiredBackgroundTimeCancelsTheScan() async {
        let harness = makeHarness()
        await harness.viewModel.startScan()
        harness.viewModel.scenePhaseChanged(to: .background)
        harness.lifecycle.expiration?()

        #expect(harness.lifecycle.ended == harness.lifecycle.begun, "Ended inside the expiration handler")
        #expect(await eventually { !harness.viewModel.isScanning })
        #expect(await harness.coordinator.cancelCallCount == 1)
    }

    @Test func deletedPhotosAreForwarded() async {
        let harness = makeHarness()
        harness.viewModel.photosDeleted(["X", "Y"])
        harness.viewModel.photosDeleted([])
        var excluded: [Set<String>] = []
        for _ in 0..<500 where excluded.isEmpty {
            excluded = await harness.coordinator.excludedIDs
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(excluded == [["X", "Y"]])
    }
}
