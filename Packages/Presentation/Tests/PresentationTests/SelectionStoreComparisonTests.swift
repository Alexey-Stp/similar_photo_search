import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// "Keep This One" and "Mark as Best" on `SelectionStore` (SPS-22).
@MainActor
struct SelectionStoreComparisonTests {
    private func makeStore() -> SelectionStore {
        let store = SelectionStore(sizes: MockAssetSizeEstimator(sizes: [:]))
        store.upsert([group(["A", "B", "C"], keeper: "A", delete: ["B"])])
        return store
    }

    private func group(_ ids: [String], keeper: String?, delete: Set<String>) -> ClusterSelection {
        ClusterSelection(
            cluster: SimilarityCluster(id: "G", assetIDs: ids, suggestedKeeperID: keeper),
            ranking: [],
            suggestedForDeletion: delete,
            needsReview: false
        )
    }

    // MARK: - Mark as Best

    @Test func markAsBestMovesTheBadgeAndKeepsThePhoto() throws {
        let store = makeStore()
        #expect(store.markAsBest("B", in: "G"))

        let state = try #require(store.state(for: "G"))
        #expect(state.keeperID == "B")
        #expect(state.chosenKeeperID == "B")
        #expect(store.isKept("B"))
        #expect(store.selectedAssetIDs.isEmpty)
        #expect(state.isOverridden)
    }

    @Test func markingTheSuggestedKeeperAgainGoesBackToTheSuggestion() throws {
        let store = makeStore()
        store.markAsBest("C", in: "G")
        store.markAsBest("A", in: "G")

        let state = try #require(store.state(for: "G"))
        #expect(state.keeperID == "A")
        #expect(state.chosenKeeperID == nil)
        #expect(!state.isOverridden)
    }

    @Test func markAsBestIgnoresUnknownClustersAndNonMembers() {
        let store = makeStore()
        #expect(!store.markAsBest("X", in: "G"))
        #expect(!store.markAsBest("A", in: "unknown"))
        #expect(store.state(for: "G")?.keeperID == "A")
    }

    @Test func theChosenBestSurvivesARescanWithTheSameMembersOnly() {
        let store = makeStore()
        store.markAsBest("C", in: "G")
        store.remove(clusterIDs: ["G"])
        store.upsert([group(["A", "B", "C"], keeper: "A", delete: ["B"])])
        #expect(store.state(for: "G")?.keeperID == "C")

        store.upsert([group(["A", "B", "C", "D"], keeper: "A", delete: ["B"])])
        #expect(store.state(for: "G")?.keeperID == "A")
    }

    @Test func smartSelectAllForgetsTheChosenBest() {
        let store = makeStore()
        store.markAsBest("C", in: "G")
        store.selectSmartAll()
        #expect(store.state(for: "G")?.keeperID == "A")
        #expect(store.selectedAssetIDs == ["B"])
    }

    // MARK: - Keep This One

    @Test func keepOnlySelectsEveryOtherPhotoAndMarksItBest() throws {
        let store = makeStore()
        #expect(store.keepOnly("C", in: "G"))

        let state = try #require(store.state(for: "G"))
        #expect(store.selectedAssetIDs == ["A", "B"])
        #expect(state.keeperID == "C")
        #expect(store.isKept("C"))
        #expect(!state.isDeleteAllConfirmed)
    }

    @Test func keepOnlyLeavesExcludedPhotosUnselected() {
        let store = makeStore()
        store.keepOnly("A", in: "G", excluding: ["C"])
        #expect(store.selectedAssetIDs == ["B"])
    }

    @Test func keepOnlyClearsAConfirmedDeleteAll() throws {
        let store = makeStore()
        store.confirmDeleteAll("G")
        store.keepOnly("B", in: "G")

        let state = try #require(store.state(for: "G"))
        #expect(!state.isDeleteAllConfirmed)
        #expect(store.selectedAssetIDs == ["A", "C"])
    }

    @Test func keepOnlyIgnoresNonMembers() {
        let store = makeStore()
        #expect(!store.keepOnly("X", in: "G"))
        #expect(store.selectedAssetIDs == ["B"])
    }
}
