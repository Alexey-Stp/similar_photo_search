import Domain
import Foundation
import Presentation
import Testing

@MainActor
struct HomeSummaryTests {
    @Test func everySkipInICloudNamesICloud() throws {
        let summary = SkippedPhotosSummary(counts: [.iCloudOnly: 128])
        let headline = try #require(summary.headline)
        #expect(headline.contains("128"))
        #expect(headline.contains("iCloud"))
    }

    @Test func mixedReasonsGiveTheTotal() throws {
        let summary = SkippedPhotosSummary(counts: [.iCloudOnly: 128, .noDate: 2])
        let headline = try #require(summary.headline)
        #expect(headline.contains("130"))
        #expect(!headline.contains("iCloud"))
        #expect(summary.rows.map(\.reason) == [.iCloudOnly, .noDate])
    }

    @Test func noSkipsGiveNoLine() {
        let summary = SkippedPhotosSummary(counts: [.iCloudOnly: 0])
        #expect(summary.isEmpty)
        #expect(summary.headline == nil)
        #expect(summary.rows.isEmpty)
    }

    @Test func reclaimableSizeIsOnlyShownWhenKnown() {
        #expect(HomeSummary(groupCount: 1, photoCount: 2).reclaimableText == nil)
        let known = HomeSummary(groupCount: 1, photoCount: 2, reclaimableBytes: 6_000_000)
        #expect(known.reclaimableText?.hasPrefix("About") == true)
        let lowerBound = HomeSummary(groupCount: 1, photoCount: 2, reclaimableBytes: 6_000_000, isLowerBound: true)
        #expect(lowerBound.reclaimableText?.hasPrefix("At least") == true)
    }
}
