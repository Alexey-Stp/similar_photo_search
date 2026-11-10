import Domain
import Testing

/// Keep / delete suggestions per cluster (SPS-18).
struct SmartSelectionUseCaseTests {
    private let useCase = SmartSelectionUseCase()
    /// Only sharpness counts, so a score is just the normalized sharpness and ties are easy to build.
    private let sharpnessOnly = SmartSelectionUseCase(
        weights: QualityWeights(sharpness: 1, faceQuality: 0, resolution: 0, aesthetics: 0)
    )

    private func cluster(_ ids: [String], exact: Bool = false) -> SimilarityCluster {
        SimilarityCluster(assetIDs: ids, isExactDuplicate: exact)
    }

    private func signals(
        _ sharpness: Float,
        pixels: Int = 100,
        favorite: Bool = false,
        edited: Bool = false
    ) -> QualitySignals {
        QualitySignals(sharpness: sharpness, pixelCount: pixels, isFavorite: favorite, isEdited: edited)
    }

    // MARK: - Keep best, select the rest

    @Test func theTopRankedMemberIsKeptAndTheOthersArePreSelected() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(1), "B": signals(10), "C": signals(5)]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.cluster.suggestedKeeperID == "B")
        #expect(selection.suggestedForDeletion == ["A", "C"])
        #expect(selection.keptIDs == ["B"])
        #expect(!selection.needsReview)
        #expect(selection.ranking.map(\.assetID) == ["B", "C", "A"])
    }

    @Test func theClusterKeepsItsIdentityAndMembers() {
        let original = SimilarityCluster(
            id: "X",
            assetIDs: ["A", "B"],
            averageDistance: 0.3,
            isExactDuplicate: false
        )
        let selection = sharpnessOnly.suggest(for: original, signals: ["A": signals(1), "B": signals(2)])
        #expect(selection.id == "X")
        #expect(selection.cluster.assetIDs == ["A", "B"])
        #expect(selection.cluster.averageDistance == 0.3)
    }

    @Test func signalsOfOtherPhotosAreIgnored() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B"]),
            signals: ["A": signals(1), "B": signals(2), "Z": signals(100)]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.ranking.map(\.assetID) == ["B", "A"])
    }

    @Test func manyClustersAreSuggestedInOrder() {
        let selections = sharpnessOnly.suggest(
            for: [cluster(["A", "B"]), cluster(["C", "D"])],
            signals: ["A": signals(1), "B": signals(2), "C": signals(4), "D": signals(3)]
        )
        #expect(selections.map(\.id) == ["A", "C"])
        #expect(selections.map(\.keeperID) == ["B", "C"])
    }

    // MARK: - Favorites

    @Test func aFavoriteIsNeverPreSelected() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(1, favorite: true), "B": signals(10), "C": signals(5)]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.suggestedForDeletion == ["C"])
        #expect(!selection.suggestedForDeletion.contains("A"))
    }

    @Test func severalFavoritesAreAllKept() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C", "D"]),
            signals: [
                "A": signals(1, favorite: true),
                "B": signals(2, favorite: true),
                "C": signals(10),
                "D": signals(5)
            ]
        )
        #expect(selection.suggestedForDeletion == ["D"])
        #expect(Set(selection.keptIDs) == ["A", "B", "C"])
    }

    @Test func aClusterOfFavoritesHasNothingPreSelected() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B"]),
            signals: ["A": signals(1, favorite: true), "B": signals(9, favorite: true)]
        )
        #expect(selection.suggestedForDeletion.isEmpty)
    }

    // MARK: - Near-ties

    @Test func membersWithinTheToleranceOfTheBestAreKeptAndFlagged() {
        // Normalized sharpness: A 1.0, B 0.99, C 0.0.
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(100), "B": signals(99), "C": signals(0)]
        )
        #expect(selection.keeperID == "A")
        #expect(selection.suggestedForDeletion == ["C"])
        #expect(selection.needsReview)
    }

    @Test func aDifferenceOfExactlyTheToleranceIsANearTie() {
        // Normalized sharpness: A 1.0, B 0.98, C 0.0.
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(50), "B": signals(49), "C": signals(0)]
        )
        #expect(selection.suggestedForDeletion == ["C"])
        #expect(selection.needsReview)
    }

    @Test func aDifferenceJustAboveTheToleranceIsNotANearTie() {
        // Normalized sharpness: A 1.0, B 0.97, C 0.0.
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(100), "B": signals(97), "C": signals(0)]
        )
        #expect(selection.suggestedForDeletion == ["B", "C"])
        #expect(!selection.needsReview)
    }

    @Test func membersWithEqualSignalsAreAllKept() {
        // No signal tells them apart, so every score is the same: nothing is pre-selected.
        let selection = useCase.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(5), "B": signals(5), "C": signals(5)]
        )
        #expect(selection.keeperID == "A")
        #expect(selection.suggestedForDeletion.isEmpty)
        #expect(selection.needsReview)
    }

    @Test func theToleranceIsConfigurable() {
        let strict = SmartSelectionUseCase(
            nearTieTolerance: 0,
            weights: QualityWeights(sharpness: 1, faceQuality: 0, resolution: 0, aesthetics: 0)
        )
        let selection = strict.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(100), "B": signals(99), "C": signals(0)]
        )
        #expect(selection.suggestedForDeletion == ["B", "C"])
        #expect(!selection.needsReview)
    }

    // MARK: - Exact duplicates

    @Test func anExactDuplicateKeepsTheHighestResolution() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"], exact: true),
            signals: [
                "A": signals(10, pixels: 100),
                "B": signals(1, pixels: 400),
                "C": signals(5, pixels: 200, edited: true)
            ]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.suggestedForDeletion == ["A", "C"])
        #expect(!selection.needsReview)
    }

    @Test func anExactDuplicateWithEqualResolutionKeepsTheEditedVersion() {
        let selection = useCase.suggest(
            for: cluster(["A", "B"], exact: true),
            signals: ["A": signals(5, pixels: 100), "B": signals(5, pixels: 100, edited: true)]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.suggestedForDeletion == ["A"])
        #expect(!selection.needsReview)
    }

    @Test func identicalExactDuplicatesKeepTheBestRankedOne() {
        let selection = useCase.suggest(
            for: cluster(["B", "A"], exact: true),
            signals: ["A": signals(5), "B": signals(5)]
        )
        // Equal scores rank by asset ID, so "A" is first.
        #expect(selection.keeperID == "A")
        #expect(selection.suggestedForDeletion == ["B"])
    }

    @Test func anExactDuplicateStillKeepsFavorites() {
        let selection = useCase.suggest(
            for: cluster(["A", "B", "C"], exact: true),
            signals: ["A": signals(5, pixels: 400), "B": signals(5, favorite: true), "C": signals(5)]
        )
        #expect(selection.keeperID == "A")
        #expect(selection.suggestedForDeletion == ["C"])
    }

    // MARK: - Unranked members

    @Test func aMemberWithoutSignalsIsNeverPreSelected() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "B", "C"]),
            signals: ["A": signals(1), "B": signals(10)]
        )
        #expect(selection.keeperID == "B")
        #expect(selection.suggestedForDeletion == ["A"])
        #expect(selection.keptIDs == ["B", "C"])
        #expect(selection.needsReview)
    }

    @Test func aClusterWithoutAnySignalsKeepsEverything() {
        let selection = useCase.suggest(for: cluster(["A", "B"]), signals: [:])
        #expect(selection.keeperID == nil)
        #expect(selection.cluster.suggestedKeeperID == nil)
        #expect(selection.suggestedForDeletion.isEmpty)
        #expect(selection.needsReview)
    }

    // MARK: - Invariant

    @Test(arguments: [false, true])
    func atLeastOneMemberIsAlwaysKept(exact: Bool) {
        for count in 1...6 {
            let ids = (0..<count).map { "P\($0)" }
            var memberSignals: [String: QualitySignals] = [:]
            for (index, id) in ids.enumerated() {
                memberSignals[id] = signals(Float(index * 10), pixels: 100 + index)
            }
            let selection = useCase.suggest(for: cluster(ids, exact: exact), signals: memberSignals)
            #expect(selection.suggestedForDeletion.count < ids.count)
            if let keeper = selection.keeperID {
                #expect(!selection.suggestedForDeletion.contains(keeper))
            }
        }
    }

    @Test func duplicateMemberIDsDoNotBreakTheInvariant() {
        let selection = sharpnessOnly.suggest(
            for: cluster(["A", "A", "B"]),
            signals: ["A": signals(1), "B": signals(10)]
        )
        #expect(selection.suggestedForDeletion == ["A"])
        #expect(selection.keeperID == "B")
    }
}
