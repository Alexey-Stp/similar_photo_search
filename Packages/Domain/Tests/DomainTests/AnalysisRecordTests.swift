import Domain
import Foundation
import Testing

struct AnalysisRecordTests {
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000.123)
    private let analyzedAt = Date(timeIntervalSince1970: 1_700_000_500)

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

    private var featurePrint: FeaturePrint {
        FeaturePrint(assetID: "A", revision: 2, vector: [1, 2, 3], assetModificationDate: modificationDate)
    }

    // MARK: - Validity

    @Test func isValidOnlyWhenIDRevisionAndModificationDateMatch() {
        let record = AnalysisRecord(featurePrint: featurePrint, analyzedAt: analyzedAt)
        #expect(record.isValid(for: asset(modified: modificationDate), revision: 2))
        #expect(!record.isValid(for: asset(modified: modificationDate), revision: 1))
        #expect(!record.isValid(for: asset(modified: modificationDate.addingTimeInterval(0.001)), revision: 2))
        #expect(!record.isValid(for: asset(modified: nil), revision: 2))
    }

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

    @Test func aComputedOutcomeBecomesAnAnalyzedRecordWithThePrint() throws {
        let record = try #require(AnalysisRecord(
            outcome: .computed(featurePrint),
            asset: asset(modified: modificationDate),
            revision: 2,
            analyzedAt: analyzedAt
        ))
        #expect(record.status == .analyzed)
        #expect(record.vector == [1, 2, 3])
        #expect(record.analyzedAt == analyzedAt)
        #expect(record.featurePrint == featurePrint)
    }

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
}
