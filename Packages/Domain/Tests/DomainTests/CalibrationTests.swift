import Domain
import DomainTestSupport
import Foundation
import Testing

/// Regression gate for clustering (SPS-28): the app's `ClusteringConfig.calibrated` on the labelled fixture set must
/// reach the SPS-15 epic target, pairwise precision ≥ 95 % and recall ≥ 80 %.
///
/// The fixture holds revision-2 feature prints of real photos, extracted on a physical device by
/// `CalibrationFixtureExtractionTests` (DataTests). These tests **fail** until it is committed: see
/// `Fixtures/README.md`. Each run prints the precision/recall curve and the session-gap table.
struct CalibrationTests {
    static let revision = 2
    static let minimumPhotos = 500
    static let minimumPrecision = 0.95
    static let minimumRecall = 0.80
    /// Thresholds of the printed curve: 0.00 to 1.50 in steps of 0.01 (revision-2 prints are unit length,
    /// so distances lie in 0…2).
    static let curveThresholds: [Float] = (0...150).map { Float($0) / 100 }

    struct FixtureMissing: Error, CustomStringConvertible {
        var description: String {
            "Fixtures/\(CalibrationTests.fixtureName).json is missing. Extract it on a physical iPhone with "
                + "CalibrationFixtureExtractionTests (RUN_CALIBRATION_EXTRACTION=1); see Fixtures/README.md."
        }
    }

    static let fixtureName = "calibration-rev2"

    static func loadFixture() throws -> CalibrationFixture {
        guard let url = Bundle.module.url(forResource: fixtureName, withExtension: "json", subdirectory: "Fixtures")
        else { throw FixtureMissing() }
        return try CalibrationFixture.decoded(from: Data(contentsOf: url))
    }

    @Test func fixtureCoversTheRequiredKindsOfPhotos() throws {
        let fixture = try Self.loadFixture()
        print(CalibrationReport.coverageTable(fixture))

        #expect(fixture.photos.count >= Self.minimumPhotos, "The labelled set needs at least 500 photos")
        #expect(fixture.photos.allSatisfy { $0.revision == Self.revision }, "Only revision-2 prints belong here")
        #expect(Set(fixture.photos.map(\.vector.count)).count == 1, "All vectors must have one length")
        #expect(Set(fixture.photos.map(\.id)).count == fixture.photos.count, "Photo IDs must be unique")
        for category in CalibrationCategory.allCases {
            let groups = Set(fixture.photos.filter { $0.category == category }.map(\.group))
            #expect(groups.count >= (category == .unrelated ? 2 : 1), "No photos of category \(category.rawValue)")
        }
        #expect(fixture.photos.contains { $0.burstIdentifier != nil }, "No photo carries a burst identifier")
    }

    @Test func calibratedThresholdMeetsTheEpicTarget() async throws {
        let evaluator = CalibrationEvaluator(fixture: try Self.loadFixture())
        let base = ClusteringConfig.calibrated
        let curve = try await evaluator.curve(thresholds: Self.curveThresholds, revision: Self.revision, base: base)
        print(CalibrationReport.curveTable(curve.filter { $0.score.truePositives > 0 || $0.threshold == 0 }))
        if let best = CalibrationEvaluator.bestPoint(on: curve, minimumPrecision: Self.minimumPrecision) {
            print("Best recall at precision ≥ 95 %: threshold \(best.threshold), \(best.score)")
        }

        let threshold = try #require(
            base.threshold(forRevision: Self.revision),
            "ClusteringConfig.calibrated has no threshold for revision 2: pick one from the curve above"
        )
        let score = try await evaluator.score(config: base, sessionConfig: .default)
        print("Calibrated threshold \(threshold): \(score)")

        #expect(score.precision >= Self.minimumPrecision, "Precision \(score.precision) is below 95 %")
        #expect(score.recall >= Self.minimumRecall, "Recall \(score.recall) is below 80 %")
    }

    @Test func defaultSessionGapKeepsEnoughLabelledPairsTogether() async throws {
        let evaluator = CalibrationEvaluator(fixture: try Self.loadFixture())
        let gaps = SessionGapPreset.allCases.map(\.interval)
        let splits = try await evaluator.sessionGapSplits(gaps: gaps)
        print(CalibrationReport.sessionGapTable(splits))

        let defaultSplit = try #require(splits.first { $0.gap == SessionConfig.default.sessionGap })
        #expect(
            defaultSplit.recallCeiling >= Self.minimumRecall,
            "The default session gap separates \(defaultSplit.splitPairs) of \(defaultSplit.labelledPairs) pairs"
        )
    }
}
