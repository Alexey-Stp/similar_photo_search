import Domain
import Testing

/// Recomputing a suggestion locally after some members were deleted (SPS-25).
struct ClusterSelectionRemovalTests {
    /// A cluster `A…D` ranked in the given order, keeping `keeper` and suggesting `deletion`.
    private func selection(
        _ ids: [String] = ["A", "B", "C", "D"],
        ranking: [String]? = nil,
        keeper: String? = "A",
        deletion: Set<String> = ["B", "C", "D"],
        needsReview: Bool = false,
        exact: Bool = false
    ) -> ClusterSelection {
        let ranked = (ranking ?? ids).enumerated().map { index, id in
            RankedMember(assetID: id, score: 1 - Double(index) / 10, isProtected: false, reasons: [])
        }
        return ClusterSelection(
            cluster: SimilarityCluster(
                id: "cluster",
                assetIDs: ids,
                suggestedKeeperID: keeper,
                averageDistance: 0.3,
                isExactDuplicate: exact
            ),
            ranking: ranked,
            suggestedForDeletion: deletion,
            needsReview: needsReview
        )
    }

    @Test func removingNoMemberReturnsTheSameSuggestion() {
        let original = selection()
        #expect(original.removingMembers(["X"]) == original)
        #expect(original.removingMembers([]) == original)
    }

    @Test func aClusterLeftWithFewerThanTwoMembersIsGone() {
        #expect(selection().removingMembers(["B", "C", "D"]) == nil)
        #expect(selection().removingMembers(["A", "B", "C", "D"]) == nil)
    }

    @Test func survivorsKeepTheirOrderTheClusterIDAndItsMetrics() throws {
        let result = try #require(selection().removingMembers(["A", "C"]))
        #expect(result.id == "cluster")
        #expect(result.cluster.assetIDs == ["B", "D"])
        #expect(result.cluster.averageDistance == 0.3)
        #expect(result.ranking.map(\.assetID) == ["B", "D"])
    }

    @Test func whenThePhotoNamingTheClusterIsDeletedTheNewestSurvivorNamesIt() throws {
        let named = ClusterSelection(
            cluster: SimilarityCluster(assetIDs: ["A", "B", "C"], suggestedKeeperID: "B"),
            ranking: [],
            suggestedForDeletion: ["A", "C"],
            needsReview: false
        )
        let result = try #require(named.removingMembers(["A"]))
        #expect(result.id == "B")
        #expect(result.id == SimilarityCluster(assetIDs: result.cluster.assetIDs).id)
    }

    @Test func aSurvivingKeeperStaysTheKeeper() throws {
        let result = try #require(selection().removingMembers(["C"]))
        #expect(result.keeperID == "A")
        #expect(result.suggestedForDeletion == ["B", "D"])
        #expect(!result.needsReview)
    }

    @Test func aDeletedKeeperIsReplacedByTheBestRankedSurvivorWhichIsKept() throws {
        let result = try #require(
            selection(ranking: ["A", "C", "B", "D"]).removingMembers(["A"])
        )
        #expect(result.keeperID == "C")
        #expect(result.cluster.suggestedKeeperID == "C")
        #expect(result.suggestedForDeletion == ["B", "D"])
        #expect(result.needsReview)
    }

    @Test func withoutARankedSurvivorThereIsNoKeeperAndNothingSuggested() throws {
        let unranked = ClusterSelection(
            cluster: SimilarityCluster(id: "cluster", assetIDs: ["A", "B", "C"], suggestedKeeperID: "A"),
            ranking: [RankedMember(assetID: "A", score: 1, isProtected: false, reasons: [])],
            suggestedForDeletion: [],
            needsReview: true
        )
        let result = try #require(unranked.removingMembers(["A"]))
        #expect(result.keeperID == nil)
        #expect(result.suggestedForDeletion.isEmpty)
        #expect(result.needsReview)
    }

    @Test func theSuggestionNeverSelectsEverySurvivor() throws {
        // A malformed input that suggests deleting everything except the deleted keeper.
        let malformed = selection(["A", "B", "C"], ranking: [], keeper: "A", deletion: ["B", "C"])
        let result = try #require(malformed.removingMembers(["A"]))
        #expect(result.keeperID == nil)
        #expect(result.suggestedForDeletion.isEmpty)
    }

    @Test func exactDuplicatesStayExactDuplicates() throws {
        let result = try #require(selection(exact: true).removingMembers(["D"]))
        #expect(result.cluster.isExactDuplicate)
    }
}
