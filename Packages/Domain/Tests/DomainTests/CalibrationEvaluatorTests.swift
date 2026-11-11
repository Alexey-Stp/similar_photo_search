import Domain
import DomainTestSupport
import Foundation
import Testing

/// The calibration tooling on a hand-made fixture whose answer is known (SPS-28).
///
/// Group `a` (3 photos, 10 s apart) clusters at 0.5. `u1` and `c1` are unrelated but look alike, so they give one
/// false positive. Group `b` is two photos 20 minutes apart: a 5 or 15 minute session gap separates them.
struct CalibrationEvaluatorTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func photo(
        _ id: String,
        _ group: String,
        seconds: TimeInterval,
        _ vector: [Float],
        category: CalibrationCategory = .reframed
    ) -> CalibrationPhoto {
        CalibrationPhoto(
            id: id,
            group: group,
            category: category,
            creationDate: start.addingTimeInterval(seconds),
            burstIdentifier: nil,
            revision: 2,
            vector: vector
        )
    }

    static let fixture = CalibrationFixture(source: "synthetic", photos: [
        photo("a1", "reframed-g1", seconds: 0, [1, 0, 0, 0]),
        photo("a2", "reframed-g1", seconds: 10, [0.95, 0.1, 0, 0]),
        photo("a3", "reframed-g1", seconds: 20, [0.9, 0.2, 0, 0]),
        photo("u1", "unrelated-g2", seconds: 30, [0, 1, 0, 0], category: .unrelated),
        photo("b1", "reframed-g3", seconds: 40, [0, 0, 1, 0]),
        photo("c1", "unrelated-g4", seconds: 50, [0, 0.98, 0.1, 0], category: .unrelated),
        photo("b2", "reframed-g3", seconds: 40 + 20 * 60, [0, 0, 1, 0.05])
    ])

    let evaluator = CalibrationEvaluator(fixture: Self.fixture)

    @Test func scoresPairsWithinSessionsAndCountsSplitPairsAsMissed() async throws {
        let score = try await evaluator.score(
            config: ClusteringConfig(thresholds: [2: 0.5]),
            sessionConfig: SessionConfig(sessionGap: 15 * 60)
        )

        #expect(score == PairwiseScore(truePositives: 3, falsePositives: 1, falseNegatives: 1))
        #expect(score.precision == 0.75)
        #expect(score.recall == 0.75)
    }

    @Test func longerSessionGapFindsThePairTakenTwentyMinutesApart() async throws {
        let score = try await evaluator.score(
            config: ClusteringConfig(thresholds: [2: 0.5]),
            sessionConfig: SessionConfig(sessionGap: 60 * 60)
        )

        #expect(score == PairwiseScore(truePositives: 4, falsePositives: 1, falseNegatives: 0))
    }

    @Test func sessionsUseTheRealSegmenterNewestFirst() async throws {
        let sessions = try await evaluator.sessions(SessionConfig(sessionGap: 15 * 60))

        #expect(sessions.map { $0.map(\.id) } == [["b2"], ["c1", "b1", "u1", "a3", "a2", "a1"]])
    }

    @Test func curveIsSortedByThresholdAndScoresEachPoint() async throws {
        let curve = try await evaluator.curve(thresholds: [0.5, 0.05], revision: 2)

        #expect(curve.map(\.threshold) == [0.05, 0.5])
        #expect(curve[0].score == PairwiseScore(truePositives: 0, falsePositives: 0, falseNegatives: 4))
        #expect(curve[0].score.precision == 1)
        #expect(curve[0].score.recall == 0)
        #expect(curve[1].score == PairwiseScore(truePositives: 3, falsePositives: 1, falseNegatives: 1))
    }

    @Test func curveKeepsTheOtherParametersOfTheBaseConfig() async throws {
        // A zero pair interval compares only photos taken at the same instant: nothing here.
        let base = ClusteringConfig(thresholds: [:], maxPairInterval: 0)
        let curve = try await evaluator.curve(thresholds: [0.5], revision: 2, base: base)

        #expect(curve[0].score.truePositives == 0)
    }

    @Test func bestPointHasTheHighestRecallAtTheRequiredPrecision() {
        let curve = [
            CurvePoint(threshold: 0.1, score: PairwiseScore(truePositives: 1, falsePositives: 0, falseNegatives: 9)),
            CurvePoint(threshold: 0.2, score: PairwiseScore(truePositives: 8, falsePositives: 0, falseNegatives: 2)),
            CurvePoint(threshold: 0.3, score: PairwiseScore(truePositives: 8, falsePositives: 0, falseNegatives: 2)),
            CurvePoint(threshold: 0.4, score: PairwiseScore(truePositives: 10, falsePositives: 5, falseNegatives: 0))
        ]

        #expect(CalibrationEvaluator.bestPoint(on: curve, minimumPrecision: 0.95)?.threshold == 0.2)
        #expect(CalibrationEvaluator.bestPoint(on: curve, minimumPrecision: 0.6)?.threshold == 0.4)
        #expect(CalibrationEvaluator.bestPoint(on: [curve[3]], minimumPrecision: 0.95) == nil)
    }

    @Test func sessionGapSplitsCountLabelledPairsInDifferentSessions() async throws {
        // Strict (5 min), Balanced (15 min), Relaxed (60 min).
        let gaps: [TimeInterval] = SessionGapPreset.allCases.map(\.interval)
        let splits: [SessionGapSplit] = try await evaluator.sessionGapSplits(gaps: gaps)

        #expect(splits.map(\.splitPairs) == [1, 1, 0])
        #expect(splits.map(\.labelledPairs) == [4, 4, 4])
        #expect(splits[0].recallCeiling == 0.75)
        #expect(splits[2].recallCeiling == 1)
    }

    @Test func emptyScoresAreNeutral() {
        let empty = PairwiseScore(truePositives: 0, falsePositives: 0, falseNegatives: 0)

        #expect(empty.precision == 1)
        #expect(empty.recall == 1)
    }

    @Test func reportTablesHaveOneRowPerEntry() async throws {
        let curve = try await evaluator.curve(thresholds: [0.05, 0.5], revision: 2)
        let gaps: [TimeInterval] = [SessionGapPreset.strict.interval, SessionGapPreset.balanced.interval]
        let splits: [SessionGapSplit] = try await evaluator.sessionGapSplits(gaps: gaps)

        let curveTable = CalibrationReport.curveTable(curve)
        #expect(curveTable.split(separator: "\n").count == 4)
        #expect(curveTable.contains("| 0.500 | 75.0 % | 75.0 % | 3 | 1 | 1 |"))
        #expect(CalibrationReport.sessionGapTable(splits).contains("| 15 min | 4 | 1 | 75.0 % |"))
        #expect(CalibrationReport.coverageTable(Self.fixture).contains("| unrelated | 2 | 2 |"))
    }
}
