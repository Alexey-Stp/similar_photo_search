import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// The scan and Home after a deletion: rows, the running scan, and no rescan for the app's own change (SPS-25).
@MainActor
struct ScanDeletionTests {
    @Test func deletedPhotosLeaveTheRowsAndTheRunningScan() async {
        let harness = DeletionHarness()
        harness.show([["A1", "A2"], ["B1", "B2", "B3"], ["C1", "C2", "C3"]])
        let revision = harness.scan.clusterRevision

        harness.scan.deletionStarted()
        await harness.scan.deletionFinished(deleted: ["A2", "B3", "C1"])

        #expect(harness.scan.rowOrder.ids == ["B1", "C2"])
        #expect(harness.scan.clusterRevision == revision + 1)
        #expect(await harness.coordinator.excludedIDs == [["A2", "B3", "C1"]])
        #expect(await harness.coordinator.startCalls.isEmpty)
    }

    @Test func aRunningScanContinuesAndItsLaterGroupsKeepTheirRows() async {
        let harness = DeletionHarness()
        await harness.scan.startScan()
        await harness.coordinator.send(.added([ClusterListHarness.group(["A1", "A2", "A3"])]))
        #expect(await harness.eventually { harness.store.clusterIDs == ["A1"] })

        await harness.scan.deletionFinished(deleted: ["A1"])
        #expect(harness.scan.isScanning)
        #expect(harness.scan.rowOrder.ids == ["A2"])

        // The scan re-publishes the shrunk group under the same ID: same row, no duplicate.
        let republished = [ClusterListHarness.group(["A2", "A3"]), ClusterListHarness.group(["D1", "D2"])]
        await harness.coordinator.send(.added(republished))
        #expect(await harness.eventually { harness.store.clusterIDs.count == 2 })
        #expect(harness.scan.rowOrder.ids == ["A2", "D1"])
        #expect(await harness.coordinator.startCalls.count == 1)
    }

    @Test func groupsPublishedBeforeTheScanLearnedOfADeletionDontBringPhotosBack() async {
        let harness = DeletionHarness()
        await harness.scan.startScan()
        await harness.coordinator.send(.added([ClusterListHarness.group(["A1", "A2", "A3"])]))
        #expect(await harness.eventually { harness.store.clusterIDs == ["A1"] })
        await harness.scan.deletionFinished(deleted: ["A1", "B2"])

        // Published by the scan before the exclusion reached it, still holding the deleted photos.
        let stale = [
            ClusterListHarness.group(["A1", "A2", "A3"]),
            ClusterListHarness.group(["B1", "B2"]),
            ClusterListHarness.group(["C1", "C2"])
        ]
        await harness.coordinator.send(.added(stale))
        #expect(await harness.eventually { harness.store.clusterIDs.count == 2 })

        #expect(harness.store.clusterIDs == ["A2", "C1"])
        #expect(harness.store.state(for: "A2")?.memberIDs == ["A2", "A3"])
        #expect(harness.scan.rowOrder.ids == ["A2", "C1"])
        #expect(!harness.store.isSelected("A1"))
    }

    @Test func nothingDeletedChangesNothing() async {
        let harness = DeletionHarness()
        harness.show([["A1", "A2"]])
        let revision = harness.scan.clusterRevision

        harness.scan.deletionStarted()
        await harness.scan.deletionFinished(deleted: [])

        #expect(harness.scan.clusterRevision == revision)
        #expect(!harness.scan.isOwnDeletionInProgress)
        #expect(await harness.coordinator.excludedIDs.isEmpty)
    }

    @Test func theLibraryChangeOfTheAppsOwnDeletionStartsNoRescan() async {
        let harness = DeletionHarness()
        let observer = MockLibraryChangeObserver()
        let home = HomeViewModel(
            scan: harness.scan,
            results: MockClusterRepository(results: []),
            libraryChanges: observer
        )
        await home.launch()
        await home.startScan()
        await harness.coordinator.send(ScanProgress(processed: 2, total: 2, phase: .done))
        await harness.coordinator.finish()
        #expect(await harness.eventually { !harness.scan.isScanning && home.hasPreviousScan })

        harness.scan.deletionStarted()
        observer.signal()
        await harness.scan.deletionFinished(deleted: ["A2"])
        observer.signal()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await harness.coordinator.startCalls.count == 1, "The app's own deletion is not rescanned")

        harness.clock.now += ScanViewModel.ownChangeQuietPeriod + 1
        #expect(!harness.scan.isOwnDeletionInProgress)
        observer.signal()
        var started = 0
        for _ in 0..<500 where started < 2 {
            started = await harness.coordinator.startCalls.count
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(started == 2, "A later change from elsewhere still rescans")
    }
}
