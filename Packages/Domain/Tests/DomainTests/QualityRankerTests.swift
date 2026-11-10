import Domain
import Foundation
import Testing

/// Weighted, per-cluster quality ranking (SPS-17).
struct QualityRankerTests {
    private let ranker = QualityRanker()

    /// The score of `id` in `ranked`.
    private func score(_ id: String, in ranked: [RankedMember]) throws -> Double {
        try #require(ranked.first { $0.assetID == id }).score
    }

    // MARK: - Weighted score

    /// The sharper photo wins when nothing else differs.
    @Test func theSharperPhotoWins() {
        let ranked = ranker.rank([
            "blurred": QualitySignals(sharpness: 0.001, pixelCount: 100),
            "sharp": QualitySignals(sharpness: 0.02, pixelCount: 100)
        ])
        #expect(ranked.map(\.assetID) == ["sharp", "blurred"])
        #expect(ranked[0].reasons == [.sharpest])
        #expect(ranked[1].reasons.isEmpty)
    }

    /// With every signal present: `0.4·sharpness + 0.4·faceQuality + 0.1·resolution + 0.1·aesthetics`.
    @Test func defaultWeightsAreFourFourOneOne() throws {
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: 9, faceQuality: 0.2, aesthetics: 0.5, pixelCount: 200),
            "B": QualitySignals(sharpness: 1, faceQuality: 0.9, aesthetics: -0.5, pixelCount: 100)
        ])
        #expect(abs(try score("A", in: ranked) - 0.6) < 1e-9)
        #expect(abs(try score("B", in: ranked) - 0.4) < 1e-9)
        #expect(ranked[0].reasons == [.sharpest, .highestResolution, .bestAesthetics])
        #expect(ranked[1].reasons == [.bestFaces])
    }

    /// Every signal is min-max normalized within the cluster.
    @Test func signalsAreMinMaxNormalizedWithinTheCluster() throws {
        let onlySharpness = QualityWeights(sharpness: 1, faceQuality: 0, resolution: 0, aesthetics: 0)
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: 10, pixelCount: 1),
            "B": QualitySignals(sharpness: 20, pixelCount: 1),
            "C": QualitySignals(sharpness: 30, pixelCount: 1)
        ], weights: onlySharpness)
        #expect(abs(try score("A", in: ranked) - 0) < 1e-9)
        #expect(abs(try score("B", in: ranked) - 0.5) < 1e-9)
        #expect(abs(try score("C", in: ranked) - 1) < 1e-9)

        // Scaling the raw values changes nothing: only the order within the cluster counts.
        let scaled = ranker.rank([
            "A": QualitySignals(sharpness: 1_000, pixelCount: 1),
            "B": QualitySignals(sharpness: 2_000, pixelCount: 1),
            "C": QualitySignals(sharpness: 3_000, pixelCount: 1)
        ], weights: onlySharpness)
        #expect(scaled.map(\.score) == ranked.map(\.score))
    }

    /// Every score is in 0…1.
    @Test func scoresStayInZeroToOne() {
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: 5, faceQuality: 1, aesthetics: 1, pixelCount: 12_000_000),
            "B": QualitySignals(sharpness: 0, faceQuality: 0, aesthetics: -1, pixelCount: 1),
            "C": QualitySignals(sharpness: 2, faceQuality: 0.5, aesthetics: 0, pixelCount: 3_000_000)
        ])
        #expect(ranked.allSatisfy { (0...1).contains($0.score) })
        #expect(ranked.first?.score == 1)
        #expect(ranked.last?.score == 0)
    }

    // MARK: - Missing signals

    /// No faces in one member: face quality is dropped for the whole cluster, and its 0.4 is spread over
    /// sharpness, resolution and aesthetics in proportion to their weights (4 : 1 : 1).
    @Test func aMissingFaceDropsFaceQualityForTheWholeClusterAndRedistributesItsWeight() throws {
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: 1, faceQuality: 1.0, aesthetics: 0, pixelCount: 200),
            "B": QualitySignals(sharpness: 3, faceQuality: 0.1, aesthetics: 1, pixelCount: 100),
            "C": QualitySignals(sharpness: 2, faceQuality: nil, aesthetics: 0.5, pixelCount: 150)
        ])
        // A: resolution only → 0.1 / 0.6. B: sharpness + aesthetics → 0.5 / 0.6. C: half of each → 0.3 / 0.6.
        #expect(abs(try score("A", in: ranked) - 0.1 / 0.6) < 1e-9)
        #expect(abs(try score("B", in: ranked) - 0.5 / 0.6) < 1e-9)
        #expect(abs(try score("C", in: ranked) - 0.3 / 0.6) < 1e-9)
        #expect(ranked.map(\.assetID) == ["B", "C", "A"])
        // A's best face does not count, so it is not given as a reason.
        #expect(!ranked.contains { $0.reasons.contains(.bestFaces) })
    }

    /// No aesthetics on any member (iOS 17): its 0.1 goes to the other three (4 : 4 : 1).
    @Test func missingAestheticsRedistributeTheirWeight() throws {
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: 2, faceQuality: 0.3, pixelCount: 100),
            "B": QualitySignals(sharpness: 1, faceQuality: 0.6, pixelCount: 100)
        ])
        // Resolution is equal (normalized 1 for both); sharpness and faces split.
        #expect(abs(try score("A", in: ranked) - 0.5 / 0.9) < 1e-9)
        #expect(abs(try score("B", in: ranked) - 0.5 / 0.9) < 1e-9)
    }

    /// No faces anywhere, the same as one member without faces.
    @Test func noFacesAtAllIsNotAZeroFaceScore() throws {
        let withoutFaces = ranker.rank([
            "A": QualitySignals(sharpness: 2, pixelCount: 100),
            "B": QualitySignals(sharpness: 1, pixelCount: 200)
        ])
        // Weights 0.4 and 0.1 only: A = 0.4 / 0.5, B = 0.1 / 0.5.
        #expect(abs(try score("A", in: withoutFaces) - 0.8) < 1e-9)
        #expect(abs(try score("B", in: withoutFaces) - 0.2) < 1e-9)
    }

    /// A non-finite value counts as missing, so it can't poison the scores.
    @Test func aNonFiniteValueCountsAsMissing() {
        let ranked = ranker.rank([
            "A": QualitySignals(sharpness: .nan, pixelCount: 100),
            "B": QualitySignals(sharpness: 1, pixelCount: 200)
        ])
        #expect(ranked.map(\.assetID) == ["B", "A"])
        #expect(ranked.allSatisfy { $0.score.isFinite })
    }

    // MARK: - Weights

    /// Weights are configurable; they need not sum to 1, and negative ones count as 0.
    @Test func weightsAreConfigurable() throws {
        let signals = [
            "sharp": QualitySignals(sharpness: 2, pixelCount: 100),
            "big": QualitySignals(sharpness: 1, pixelCount: 400)
        ]
        let byResolution = ranker.rank(
            signals,
            weights: QualityWeights(sharpness: 1, faceQuality: 0, resolution: 3, aesthetics: 0)
        )
        #expect(byResolution.map(\.assetID) == ["big", "sharp"])
        #expect(abs(try score("big", in: byResolution) - 0.75) < 1e-9)

        let negative = ranker.rank(
            signals,
            weights: QualityWeights(sharpness: 1, faceQuality: 0, resolution: -5, aesthetics: 0)
        )
        #expect(negative.map(\.assetID) == ["sharp", "big"])
        #expect(negative.map(\.score) == [1, 0])
    }

    /// With no usable weight, every score is 0 and the order is by asset ID.
    @Test func noUsableWeightGivesZeroScores() {
        let ranked = ranker.rank(
            ["B": QualitySignals(sharpness: 2, pixelCount: 1), "A": QualitySignals(sharpness: 1, pixelCount: 1)],
            weights: QualityWeights(sharpness: 0, faceQuality: 1, resolution: 0, aesthetics: 0)
        )
        #expect(ranked.map(\.assetID) == ["A", "B"])
        #expect(ranked.map(\.score) == [0, 0])
    }

    // MARK: - Favorites

    /// A favorite is protected whatever its score, and keeps its place in the ranking.
    @Test func favoritesAreAlwaysProtected() {
        let ranked = ranker.rank([
            "sharp": QualitySignals(sharpness: 9, pixelCount: 100),
            "favorite": QualitySignals(sharpness: 1, pixelCount: 100, isFavorite: true)
        ])
        #expect(ranked.map(\.assetID) == ["sharp", "favorite"])
        #expect(ranked[1].score < ranked[0].score)
        #expect(ranked[1].isProtected)
        #expect(ranked[1].reasons == [.favorite])
        #expect(!ranked[0].isProtected)
    }

    // MARK: - Edge cases

    /// Empty input gives no members.
    @Test func emptyInputGivesNothing() {
        #expect(ranker.rank([:]).isEmpty)
    }

    /// A signal equal for every member normalizes to 1 and gives no reason; a single member scores 1.
    @Test func aConstantSignalMovesNoOne() {
        let single = ranker.rank(["A": QualitySignals(sharpness: 3, faceQuality: 0.4, pixelCount: 10)])
        #expect(single == [RankedMember(assetID: "A", score: 1, isProtected: false, reasons: [])])

        let equal = ranker.rank([
            "B": QualitySignals(sharpness: 3, pixelCount: 10),
            "A": QualitySignals(sharpness: 3, pixelCount: 10)
        ])
        #expect(equal.map(\.assetID) == ["A", "B"])
        #expect(equal.map(\.score) == [1, 1])
        #expect(equal.allSatisfy { $0.reasons.isEmpty })
    }

    /// The same input always gives the same ranking.
    @Test func isDeterministic() {
        var signals: [String: QualitySignals] = [:]
        for index in 0..<20 {
            signals["id\(index)"] = QualitySignals(sharpness: Float(index % 4), pixelCount: 100)
        }
        let first = ranker.rank(signals)
        for _ in 0..<5 {
            #expect(ranker.rank(signals) == first)
        }
    }

    /// Reason keys are localization keys, never English text.
    @Test func reasonsAreLocalizationKeys() {
        #expect(QualityReason.allCases.allSatisfy { $0.rawValue.hasPrefix("quality.reason.") })
    }

    // MARK: - Signals from a measurement

    /// Resolution and favorite come from the current photo, everything else from the (possibly cached) measurement.
    @Test func signalsCombineAMeasurementWithTheCurrentAssetMetadata() {
        let measurement = QualityMeasurement(
            version: 7,
            sharpness: 0.5,
            faceQuality: nil,
            aesthetics: 0.2,
            isUtility: false,
            isEdited: true
        )
        let asset = PhotoAsset(
            id: "A",
            creationDate: nil,
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            isFavorite: true,
            mediaSubtypes: []
        )
        let signals = QualitySignals(measurement: measurement, asset: asset)
        #expect(signals == QualitySignals(
            sharpness: 0.5,
            faceQuality: nil,
            aesthetics: 0.2,
            isUtility: false,
            pixelCount: 4_032 * 3_024,
            isFavorite: true,
            isEdited: true
        ))
    }
}
