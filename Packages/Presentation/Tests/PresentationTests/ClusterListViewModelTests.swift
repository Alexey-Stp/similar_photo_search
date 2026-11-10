import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// Live updates, filters, size sort and selection of the group list.
@MainActor
struct ClusterListViewModelTests {
    private typealias Harness = ClusterListHarness

    // MARK: - Live updates

    @Test func newGroupsOfARunningScanAreAppended() async {
        let harness = Harness()
        await harness.scan.startScan()
        await harness.publish([Harness.group(["C1", "C2"])])
        await harness.publish([Harness.group(["B1", "B2"]), Harness.group(["A1", "A2"])])
        #expect(harness.list.rows == ["C1", "B1", "A1"])
    }

    @Test func groupsNewerThanTheFirstRowAreInsertedAboveIt() async {
        let harness = Harness()
        harness.scan.showStoredResults([Harness.group(["B1", "B2"]), Harness.group(["A1", "A2"])])

        // A live rescan found newer photos: their group comes before the re-published ones.
        await harness.scan.startScan()
        await harness.publish([Harness.group(["N1", "N2"])])
        await harness.publish([Harness.group(["B1", "B2"])])
        await harness.publish([Harness.group(["M1", "M2"])])
        #expect(harness.list.rows == ["N1", "B1", "A1", "M1"])
    }

    @Test func replacingAGroupKeepsTheUsersChoice() async {
        let harness = Harness()
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"])])
        harness.list.toggle("A2", in: "A1")
        await harness.publish([Harness.group(["A1", "A2"])])
        #expect(harness.list.selection.isSelected("A2") == false, "The override survives the re-publish")
        #expect(harness.list.rows == ["A1"])
    }

    @Test func theFooterShowsTheProgressWhileScanning() async {
        let harness = Harness()
        #expect(harness.list.scanFooterText == nil)
        await harness.scan.startScan()
        await harness.coordinator.send(ScanProgress(processed: 4_210, total: 18_000, phase: .analyzing))
        _ = await harness.eventually { harness.scan.progress?.processed == 4_210 }
        let text = harness.list.scanFooterText ?? ""
        #expect(text.contains("4") && text.contains("18"))
        await harness.coordinator.finish()
        _ = await harness.eventually { !harness.scan.isScanning }
        #expect(harness.list.scanFooterText == nil)
    }

    // MARK: - Filters

    @Test func filtersShowOnlyMatchingGroups() async {
        let harness = Harness()
        await harness.scan.startScan()
        await harness.publish([
            Harness.group(["A1", "A2"], needsReview: true),
            Harness.group(["B1", "B2"], exact: true),
            Harness.group(["C1", "C2"])
        ])
        harness.list.filter = .needsReview
        #expect(harness.list.rows == ["A1"])
        harness.list.filter = .exactDuplicates
        #expect(harness.list.rows == ["B1"])
        harness.list.filter = .all
        #expect(harness.list.rows == ["A1", "B1", "C1"])
    }

    // MARK: - Size sort

    @Test func sizeSortPutsTheLargestReclaimableSizeFirst() async {
        let harness = Harness(sizes: ["A1": 10, "A2": 5, "B1": 1, "B2": 50, "B3": 40])
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"]), Harness.group(["B1", "B2", "B3"])])
        #expect(harness.list.reclaimableBytes(of: "A1") == 5, "Everything but the keeper")
        #expect(harness.list.reclaimableBytes(of: "B1") == 90)

        harness.list.sort = .reclaimableSize
        #expect(harness.list.rows == ["B1", "A1"])
        harness.list.sort = .date
        #expect(harness.list.rows == ["A1", "B1"])
    }

    @Test func withoutAKeeperTheLargestPhotoIsKept() async {
        let harness = Harness(sizes: ["A1": 10, "A2": 30])
        harness.scan.showStoredResults([
            ClusterSelection(unsuggested: SimilarityCluster(assetIDs: ["A1", "A2"]))
        ])
        harness.list.clustersChanged()
        await harness.list.waitForLoads()
        #expect(harness.list.reclaimableBytes(of: "A1") == 10)
    }

    @Test func groupsArrivingWhileScrollingAreSortedInWhenScrollingEnds() async {
        let harness = Harness(sizes: ["A1": 1, "A2": 1, "B1": 1, "B2": 100])
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"])])
        harness.list.sort = .reclaimableSize

        harness.list.interactionChanged(isInteracting: true)
        await harness.publish([Harness.group(["B1", "B2"])])
        #expect(harness.list.rows == ["A1"], "Nothing is inserted under the user's finger")

        harness.list.interactionChanged(isInteracting: false)
        #expect(harness.list.rows == ["B1", "A1"])
    }

    // MARK: - Selection

    @Test func selectingTheLastKeptPhotoAsksFirst() async {
        let harness = Harness()
        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2"])])
        harness.list.toggle("A1", in: "A1")
        #expect(harness.list.pendingDeleteAllClusterID == "A1")
        #expect(!harness.list.selection.isSelected("A1"), "Nothing changes before the confirmation")

        harness.list.confirmDeleteAll()
        #expect(harness.list.selection.isSelected("A1"))
        #expect(harness.list.pendingDeleteAllClusterID == nil)
    }

    @Test func theDeleteButtonRecordsTheSelectionWithoutDeleting() async {
        let harness = Harness()
        harness.list.requestDeletion()
        #expect(harness.list.deletionRequest == nil, "Nothing selected, nothing requested")

        await harness.scan.startScan()
        await harness.publish([Harness.group(["A1", "A2", "A3"])])
        harness.list.requestDeletion()
        #expect(harness.list.deletionRequest?.assetIDs == ["A2", "A3"])
    }
}
