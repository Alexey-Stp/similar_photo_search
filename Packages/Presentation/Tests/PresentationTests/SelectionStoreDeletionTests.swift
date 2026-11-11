import Domain
import DomainTestSupport
import Presentation
import Testing

/// Updating the groups locally after a deletion (SPS-25).
@MainActor
struct SelectionStoreDeletionTests {
    /// A store with groups that keep their first photo and suggest deleting the others.
    private func makeStore(_ groups: [[String]]) -> SelectionStore {
        let store = SelectionStore(sizes: MockAssetSizeEstimator())
        store.upsert(groups.map { ClusterListHarness.group($0) })
        return store
    }

    @Test func aGroupLeftWithOnePhotoIsRemovedAndNothingStaysSelected() {
        let store = makeStore([["A1", "A2"], ["B1", "B2", "B3"]])

        let update = store.removeDeleted(["A2"])

        #expect(update.removed == ["A1"])
        #expect(update.updated.isEmpty)
        #expect(store.clusterIDs == ["B1"])
        #expect(store.selectedAssetIDs == ["B2", "B3"])
        #expect(store.selectedCount == 2)
        #expect(!store.isSelected("A2"))
    }

    @Test func unknownPhotosChangeNothing() {
        let store = makeStore([["A1", "A2"]])
        #expect(store.removeDeleted(["X"]).isEmpty)
        #expect(store.removeDeleted([]).isEmpty)
        #expect(store.clusterIDs == ["A1"])
    }

    @Test func survivorsKeepTheUsersChoice() throws {
        let store = makeStore([["A1", "A2", "A3", "A4"]])
        store.toggle("A3", in: "A1")  // the user keeps A3

        let update = store.removeDeleted(["A2"])

        #expect(update.updated == ["A1"])
        let state = try #require(store.state(for: "A1"))
        #expect(state.memberIDs == ["A1", "A3", "A4"])
        #expect(state.selectedIDs == ["A4"])
        #expect(state.keeperID == "A1")
        #expect(store.selectedAssetIDs == ["A4"])
    }

    @Test func aChosenBestThatSurvivedStaysTheBest() throws {
        let store = makeStore([["A1", "A2", "A3", "A4"]])
        store.markAsBest("A3", in: "A1")

        store.removeDeleted(["A2"])

        #expect(try #require(store.state(for: "A1")).keeperID == "A3")
    }

    @Test func aDeletedGroupNameIsReplacedByTheNewestSurvivorInTheSameRow() throws {
        let store = makeStore([["Z1", "Z2"], ["A1", "A2", "A3"], ["C1", "C2"]])
        // The user selects A1 and A2 and keeps A3; only A1 is deleted (A2 failed).
        store.toggle("A3", in: "A1")
        store.toggle("A1", in: "A1")

        let update = store.removeDeleted(["A1"])

        #expect(update.renamed == ["A1": "A2"])
        #expect(update.updated == ["A2"])
        #expect(store.clusterIDs == ["Z1", "A2", "C1"])
        #expect(store.state(for: "A1") == nil)
        let state = try #require(store.state(for: "A2"))
        #expect(state.memberIDs == ["A2", "A3"])
        #expect(state.selectedIDs == ["A2"])
        #expect(store.isKept("A3"))
    }

    @Test func aRescanWithTheSameSurvivorsRestoresTheChoice() throws {
        let store = makeStore([["A1", "A2", "A3", "A4"]])
        store.toggle("A3", in: "A1")
        store.removeDeleted(["A2"])

        // The scan re-publishes the shrunk group with a fresh suggestion that keeps A1 and selects A3, A4.
        store.upsert([ClusterListHarness.group(["A1", "A3", "A4"])])

        #expect(try #require(store.state(for: "A1")).selectedIDs == ["A4"])
    }

    @Test func aConfirmedDeleteAllStaysConfirmedWhileEverySurvivorIsSelected() throws {
        let store = makeStore([["A1", "A2", "A3"]])
        store.confirmDeleteAll("A1")

        store.removeDeleted(["A1"])

        let state = try #require(store.state(for: "A2"))
        #expect(state.selectedIDs == ["A2", "A3"])
        #expect(state.isDeleteAllConfirmed)
    }
}
