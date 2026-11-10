import Domain
import Foundation
import Testing

struct StoredResultsLaunchTests {
    private func result(
        newestID: String,
        at seconds: TimeInterval?,
        clusters: [[String]]
    ) -> StoredSessionResult {
        let sessionID = seconds.map {
            PhotoSession.id(newestID: newestID, newestDate: Date(timeIntervalSince1970: $0))
        } ?? newestID
        return StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: sessionID,
                content: SessionFingerprint.Content(memberCount: clusters.joined().count, digest: 1)
            ),
            clusters: clusters.map { SimilarityCluster(assetIDs: $0) },
            resultsKey: "key"
        )
    }

    @Test func newestDateIsReadBackFromTheSessionID() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_123.456)
        let id = PhotoSession.id(newestID: "ABC/L0/001@weird", newestDate: date)
        let parsed = try #require(PhotoSession.newestDate(fromID: id))
        #expect(abs(parsed.timeIntervalSince1970 - date.timeIntervalSince1970) < 0.001)
    }

    @Test(arguments: ["", "no-date", "id@", "id@abc", "@12x"])
    func malformedSessionIDsHaveNoDate(id: String) {
        #expect(PhotoSession.newestDate(fromID: id) == nil)
    }

    @Test func sessionsAreOrderedNewestFirstAndUndatedLast() {
        let stored = [
            result(newestID: "old", at: 100, clusters: [["O1", "O2"]]),
            result(newestID: "undated", at: nil, clusters: [["U1", "U2"]]),
            result(newestID: "new", at: 300, clusters: [["N1", "N2"], ["N3", "N4"]]),
            result(newestID: "mid", at: 200, clusters: [])
        ]
        let selections = StoredSessionResult.launchSelections(from: stored)
        #expect(selections.map(\.id) == ["N1", "N3", "O1", "U1"])
    }

    @Test func equalDatesAreOrderedBySessionID() {
        let stored = [
            result(newestID: "B", at: 100, clusters: [["B1", "B2"]]),
            result(newestID: "A", at: 100, clusters: [["A1", "A2"]])
        ]
        #expect(StoredSessionResult.launchSelections(from: stored).map(\.id) == ["A1", "B1"])
    }

    @Test func storedClustersKeepEveryPhotoUntilTheScanSuggests() throws {
        let stored = [result(newestID: "S", at: 100, clusters: [["S1", "S2", "S3"]])]
        let selection = try #require(StoredSessionResult.launchSelections(from: stored).first)
        #expect(selection.cluster.assetIDs == ["S1", "S2", "S3"])
        #expect(selection.suggestedForDeletion.isEmpty, "Nothing is pre-selected without a fresh suggestion")
        #expect(selection.keeperID == nil)
        #expect(selection.ranking.isEmpty)
        #expect(!selection.needsReview)
    }

    @Test func aClusterIDIsPublishedOnce() {
        let stored = [
            result(newestID: "new", at: 300, clusters: [["X1", "X2"]]),
            result(newestID: "old", at: 100, clusters: [["X1", "X3"]])
        ]
        let selections = StoredSessionResult.launchSelections(from: stored)
        #expect(selections.map(\.id) == ["X1"])
        #expect(selections.first?.cluster.assetIDs == ["X1", "X2"])
    }
}
