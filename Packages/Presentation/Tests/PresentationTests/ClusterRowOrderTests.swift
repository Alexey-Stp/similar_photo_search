import Presentation
import Testing

struct ClusterRowOrderTests {
    @Test func theFirstScanAppendsInPublishingOrder() {
        var order = ClusterRowOrder()
        order.scanStarted()
        order.add(["C", "B"])
        order.add(["A"])
        #expect(order.ids == ["C", "B", "A"])
    }

    @Test func groupsNewerThanEveryRowGoOnTopInArrivalOrder() {
        var order = ClusterRowOrder()
        order.add(["C", "B", "A"])

        order.scanStarted()
        order.add(["E"])
        order.add(["D", "C"])
        order.add(["B", "A"])
        #expect(order.ids == ["E", "D", "C", "B", "A"])
    }

    @Test func afterTheScanReachesAShownRowNewGroupsAreAppended() {
        var order = ClusterRowOrder()
        order.add(["C", "A"])

        order.scanStarted()
        order.add(["C", "B", "A"])
        #expect(order.ids == ["C", "A", "B"], "Rows never move; a new group in the middle goes to the end")
    }

    @Test func shownRowsKeepTheirPlaceWhenRepublished() {
        var order = ClusterRowOrder()
        order.add(["C", "B", "A"])
        order.scanStarted()
        order.add(["A", "B", "C"])
        #expect(order.ids == ["C", "B", "A"])
    }

    @Test func removalsKeepTheTopInsertionPointInPlace() {
        var order = ClusterRowOrder()
        order.add(["C", "B"])
        order.scanStarted()
        order.add(["F", "E"])
        order.remove(["F", "unknown"])
        order.add(["D"])
        #expect(order.ids == ["E", "D", "C", "B"])
    }

    @Test func aRemovedGroupThatComesBackIsNewAgain() {
        var order = ClusterRowOrder()
        order.add(["B", "A"])
        order.remove(["B"])
        order.scanStarted()
        order.add(["B", "A"])
        #expect(order.ids == ["B", "A"], "B arrived before A was re-published, so it is newer: on top")
    }
}
