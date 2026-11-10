import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

/// The user's keep / delete choice on top of Smart Selection (SPS-18).
@MainActor
struct SelectionStoreTests {
    private func suggestion(
        _ ids: [String],
        delete: Set<String>,
        id: String? = nil,
        needsReview: Bool = false
    ) -> ClusterSelection {
        ClusterSelection(
            cluster: SimilarityCluster(id: id, assetIDs: ids, suggestedKeeperID: ids.first { !delete.contains($0) }),
            ranking: [],
            suggestedForDeletion: delete,
            needsReview: needsReview
        )
    }

    private func makeStore(sizes: [String: Int64] = [:]) -> (SelectionStore, MockAssetSizeEstimator) {
        let estimator = MockAssetSizeEstimator(sizes: sizes)
        return (SelectionStore(sizes: estimator), estimator)
    }

    // MARK: - Suggestions

    @Test func clustersStartFromTheirSuggestion() throws {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"]), suggestion(["D", "E"], delete: ["E"])])

        #expect(store.clusterIDs == ["A", "D"])
        #expect(store.selectedCount == 3)
        #expect(store.selectedAssetIDs == ["B", "C", "E"])
        #expect(store.isKept("A"))
        #expect(!store.isKept("B"))
        #expect(store.isSelected("E"))
        #expect(!store.isKept("unknown"))
        let state = try #require(store.state(for: "A"))
        #expect(state.keeperID == "A")
        #expect(!state.isOverridden)
    }

    @Test func newClustersAreAppendedInArrivalOrder() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B"], delete: ["B"])])
        store.upsert([suggestion(["C", "D"], delete: ["D"])])
        store.upsert([suggestion(["A", "B"], delete: [])])
        #expect(store.clusterIDs == ["A", "C"])
    }

    // MARK: - Overrides

    @Test func theUserCanOverrideAnyPhoto() throws {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])

        #expect(store.toggle("B", in: "A") == .deselected)
        #expect(store.toggle("A", in: "A") == .selected)
        #expect(store.selectedAssetIDs == ["A", "C"])
        #expect(try #require(store.state(for: "A")).isOverridden)
        #expect(store.toggle("Z", in: "A") == .notFound)
        #expect(store.toggle("A", in: "nope") == .notFound)
    }

    @Test func overridesSurviveAReclusterWithTheSameMembers() throws {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        store.toggle("C", in: "A")

        // A rescan delivers the same cluster with a different suggestion.
        store.remove(clusterIDs: ["A"])
        #expect(store.selectedCount == 0)
        store.upsert([suggestion(["A", "B", "C"], delete: ["C"])])

        #expect(store.selectedAssetIDs == ["B"])
        #expect(try #require(store.state(for: "A")).isOverridden)
    }

    @Test func overridesAreDroppedWhenTheMembersChange() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        store.toggle("C", in: "A")

        store.upsert([suggestion(["A", "B", "D"], delete: ["B", "D"])])
        #expect(store.selectedAssetIDs == ["B", "D"])

        // The old members coming back later don't resurrect the dropped choice either.
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        #expect(store.selectedAssetIDs == ["B", "C"])
    }

    @Test func undoingAnOverrideFollowsTheNextSuggestion() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        store.toggle("C", in: "A")
        store.toggle("C", in: "A")

        store.upsert([suggestion(["A", "B", "C"], delete: ["C"])])
        #expect(store.selectedAssetIDs == ["C"])
    }

    // MARK: - Invariant

    @Test func selectingTheLastKeptPhotoNeedsConfirmation() throws {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])

        #expect(store.toggle("A", in: "A") == .needsConfirmation)
        #expect(store.selectedAssetIDs == ["B", "C"])
        #expect(store.isKept("A"))

        store.confirmDeleteAll("A")
        let state = try #require(store.state(for: "A"))
        #expect(store.selectedAssetIDs == ["A", "B", "C"])
        #expect(state.isDeleteAllConfirmed)

        // Keeping one photo again ends the confirmation; selecting it again needs a new one.
        #expect(store.toggle("B", in: "A") == .deselected)
        #expect(!state.isDeleteAllConfirmed)
        #expect(store.toggle("B", in: "A") == .needsConfirmation)
    }

    @Test func aConfirmedDeleteAllSurvivesAReclusterWithTheSameMembers() throws {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B"], delete: ["B"])])
        store.confirmDeleteAll("A")
        store.upsert([suggestion(["A", "B"], delete: ["B"])])
        #expect(store.selectedAssetIDs == ["A", "B"])
        #expect(try #require(store.state(for: "A")).isDeleteAllConfirmed)
    }

    @Test func aSuggestionThatSelectsEveryMemberIsRejected() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B"], delete: ["A", "B"])])
        #expect(store.selectedCount == 0)
        #expect(store.isKept("A"))
    }

    @Test func aSingleMemberClusterCannotBeSelectedWithoutConfirmation() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A"], delete: [])])
        #expect(store.toggle("A", in: "A") == .needsConfirmation)
        #expect(store.selectedCount == 0)
    }

    // MARK: - Global actions

    @Test func smartSelectAllResetsEveryClusterToItsSuggestion() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"]), suggestion(["D", "E"], delete: ["E"])])
        store.toggle("B", in: "A")
        store.confirmDeleteAll("D")

        store.selectSmartAll()
        #expect(store.selectedAssetIDs == ["B", "C", "E"])
        #expect(store.state(for: "D")?.isDeleteAllConfirmed == false)

        // The reset forgot the overrides too.
        store.upsert([suggestion(["A", "B", "C"], delete: ["C"])])
        #expect(store.selectedAssetIDs == ["C", "E"])
    }

    @Test func deselectAllKeepsEveryPhotoAcrossARecluster() {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"]), suggestion(["D", "E"], delete: ["E"])])

        store.deselectAll()
        #expect(store.selectedCount == 0)
        #expect(store.isKept("B") && store.isKept("E"))

        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        #expect(store.selectedCount == 0)
    }

    // MARK: - Summary

    @Test func theSummaryAddsTheEstimatedSizesOfSelectedPhotos() async {
        let (store, estimator) = makeStore(sizes: ["B": 1_000, "C": 2_000, "E": 500])
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"]), suggestion(["D", "E"], delete: ["E"])])
        #expect(store.summary.isEstimating)
        #expect(store.summary.estimatedBytes == nil)

        await store.waitForSizeEstimate()
        #expect(store.summary.photoCount == 3)
        #expect(store.summary.estimatedBytes == 3_500)
        #expect(!store.summary.isLowerBound)
        #expect(estimator.calls.last == ["B", "C", "E"])

        // Known sizes are not asked for again.
        store.toggle("C", in: "A")
        await store.waitForSizeEstimate()
        #expect(store.summary.estimatedBytes == 1_500)
        store.toggle("C", in: "A")
        await store.waitForSizeEstimate()
        #expect(store.summary.estimatedBytes == 3_500)
        #expect(estimator.calls.count == 1)
    }

    @Test func unavailableSizesMakeTheEstimateALowerBound() async {
        let (store, _) = makeStore(sizes: ["B": 1_000])
        store.upsert([suggestion(["A", "B", "C"], delete: ["B", "C"])])
        await store.waitForSizeEstimate()
        #expect(store.summary.unavailableCount == 1)
        #expect(store.summary.isLowerBound)
        #expect(store.summary.estimatedBytes == 1_000)
    }

    @Test func noSizeAtAllIsUnavailable() async {
        let (store, _) = makeStore()
        store.upsert([suggestion(["A", "B"], delete: ["B"])])
        await store.waitForSizeEstimate()
        #expect(store.summary.photoCount == 1)
        #expect(store.summary.estimatedBytes == nil)
        #expect(!store.summary.isEstimating)
    }

    @Test func theSummaryTextNamesCountAndSize() {
        let none = DeletionSummary(photoCount: 0, knownBytes: 0, unavailableCount: 0, pendingCount: 0)
        let full = DeletionSummary(photoCount: 38, knownBytes: 214_000_000, unavailableCount: 0, pendingCount: 0)
        let partial = DeletionSummary(photoCount: 2, knownBytes: 1_000_000, unavailableCount: 1, pendingCount: 0)
        let unknown = DeletionSummary(photoCount: 1, knownBytes: 0, unavailableCount: 1, pendingCount: 0)
        let estimating = DeletionSummary(photoCount: 5, knownBytes: 0, unavailableCount: 0, pendingCount: 5)

        #expect(none.text == "No photos selected")
        #expect(full.text.hasPrefix("38 photos, about "))
        #expect(full.text.contains("214"))
        #expect(full.text.hasSuffix(" will be deleted"))
        #expect(partial.text.hasPrefix("2 photos, at least "))
        #expect(unknown.text == "1 photo will be deleted (size unavailable)")
        #expect(estimating.text == "5 photos will be deleted. Estimating size…")
    }
}
