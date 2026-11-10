import Domain
import Foundation
import Testing

/// The cache validity rule and the mapping of feature-print outcomes to records.
struct AnalysisRecordTests {
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000.123)
    private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_500)

    /// Photo `A` with the given modification date.
    private func asset(modified: Date?) -> PhotoAsset {
        PhotoAsset(
            id: "A",
            creationDate: modificationDate,
            modificationDate: modified,
            pixelWidth: 100,
            pixelHeight: 100,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A Revision 2 print of photo `A`, modified at `modificationDate`.
    private var featurePrint: FeaturePrint {
        FeaturePrint(assetID: "A", revision: 2, vector: [1, 2, 3], assetModificationDate: modificationDate)
    }

    // MARK: - Validity

    /// A record is valid only for the same revision and the exact same modification date.
    @Test func isValidOnlyWhenIDRevisionAndModificationDateMatch() {
        let record = AnalysisRecord(featurePrint: featurePrint, analyzedAt: analyzedAt)
        #expect(record.isValid(for: asset(modified: modificationDate), revision: 2))
        #expect(!record.isValid(for: asset(modified: modificationDate), revision: 1))
        #expect(!record.isValid(for: asset(modified: modificationDate.addingTimeInterval(0.001)), revision: 2))
        #expect(!record.isValid(for: asset(modified: nil), revision: 2))
    }

    /// A record without a modification date matches only a photo without one.
    @Test func aMissingModificationDateMatchesOnlyAMissingOne() {
        let record = AnalysisRecord(
            assetID: "A",
            revision: 2,
            assetModificationDate: nil,
            status: .failed,
            analyzedAt: analyzedAt
        )
        #expect(record.isValid(for: asset(modified: nil), revision: 2))
        #expect(!record.isValid(for: asset(modified: modificationDate), revision: 2))
    }

    /// A record never matches another photo.
    @Test func isNotValidForAnotherAsset() {
        let record = AnalysisRecord(featurePrint: featurePrint, analyzedAt: analyzedAt)
        let other = PhotoAsset(
            id: "B",
            creationDate: modificationDate,
            modificationDate: modificationDate,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: []
        )
        #expect(!record.isValid(for: other, revision: 2))
    }

    // MARK: - Outcomes

    /// The record keeps the print's own revision and modification date, even when the asset and the revision passed in
    /// disagree with them.
    @Test func aComputedOutcomeBecomesAnAnalyzedRecordWithThePrint() throws {
        let record = try #require(AnalysisRecord(
            outcome: .computed(featurePrint),
            asset: asset(modified: modificationDate.addingTimeInterval(3_600)),
            revision: 3,
            analyzedAt: analyzedAt
        ))
        #expect(record.status == .analyzed)
        #expect(record.revision == 2)
        #expect(record.assetModificationDate == modificationDate)
        #expect(record.vector == [1, 2, 3])
        #expect(record.analyzedAt == analyzedAt)
        #expect(record.featurePrint == featurePrint)
    }

    /// A Vision failure is cached without a vector, under the current revision and the photo's date.
    @Test func aFailedOutcomeIsCachedUnderTheCurrentRevisionAndModificationDate() throws {
        let record = try #require(AnalysisRecord(
            outcome: .failed(.vision),
            asset: asset(modified: modificationDate),
            revision: 2,
            analyzedAt: analyzedAt
        ))
        #expect(record.status == .failed)
        #expect(record.vector.isEmpty)
        #expect(record.featurePrint == nil)
        #expect(record.isValid(for: asset(modified: modificationDate), revision: 2))
    }

    /// No skip reason produces a record.
    @Test func aSkippedOutcomeIsNotCached() {
        for reason in SkipReason.allCases {
            let record = AnalysisRecord(
                outcome: .skipped(reason),
                asset: asset(modified: modificationDate),
                revision: 2,
                analyzedAt: analyzedAt
            )
            #expect(record == nil)
        }
    }

    // MARK: - Quality

    /// A cached measurement is used only under the scoring version it was made with.
    @Test func qualityIsReturnedOnlyForItsScoringVersion() {
        let measurement = QualityMeasurement(
            version: 1_021,
            sharpness: 0.01,
            faceQuality: nil,
            aesthetics: nil,
            isUtility: nil,
            isEdited: false
        )
        let record = AnalysisRecord(featurePrint: featurePrint, quality: measurement, analyzedAt: analyzedAt)
        #expect(record.quality(scoringVersion: 1_021) == measurement)
        #expect(record.quality(scoringVersion: 1_020) == nil)
        let unscored = AnalysisRecord(featurePrint: featurePrint, analyzedAt: analyzedAt)
        #expect(unscored.quality(scoringVersion: 1_021) == nil)
    }

    /// Adding a measurement keeps the print, its validity and the analysis date.
    @Test func withQualityKeepsEverythingElse() {
        let record = AnalysisRecord(featurePrint: featurePrint, analyzedAt: analyzedAt)
        let measurement = QualityMeasurement(
            version: 1,
            sharpness: 2,
            faceQuality: 0.5,
            aesthetics: 0.1,
            isUtility: false,
            isEdited: true
        )
        let scored = record.withQuality(measurement)
        #expect(scored.quality == measurement)
        #expect(scored.featurePrint == featurePrint)
        #expect(scored.analyzedAt == analyzedAt)
        #expect(scored.isValid(for: asset(modified: modificationDate), revision: 2))
        #expect(scored.withQuality(nil) == record)
    }
}
