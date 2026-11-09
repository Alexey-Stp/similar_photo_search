import Domain
import Testing

struct LibraryDeltaTests {
    @Test func insertedThenUpdatedStaysInserted() {
        var delta = LibraryDelta()
        delta.record(inserted: ["a"], updated: [], deleted: [])
        delta.record(inserted: [], updated: ["a", "b"], deleted: [])
        #expect(delta.inserted == ["a"])
        #expect(delta.updated == ["b"])
        #expect(delta.deleted.isEmpty)
    }

    @Test func deletedAfterInsertOrUpdateIsOnlyDeleted() {
        var delta = LibraryDelta()
        delta.record(inserted: ["a"], updated: ["b"], deleted: [])
        delta.record(inserted: [], updated: [], deleted: ["a", "b"])
        #expect(delta.inserted.isEmpty)
        #expect(delta.updated.isEmpty)
        #expect(delta.deleted == ["a", "b"])
    }

    @Test func reinsertedAfterDeleteIsInserted() {
        var delta = LibraryDelta()
        delta.record(inserted: [], updated: [], deleted: ["a"])
        delta.record(inserted: ["a"], updated: [], deleted: [])
        #expect(delta.inserted == ["a"])
        #expect(delta.deleted.isEmpty)
    }

    @Test func initKeepsTheSetsDisjoint() {
        let delta = LibraryDelta(inserted: ["a", "x"], updated: ["a", "b"], deleted: ["x"])
        #expect(delta.inserted == ["a"])
        #expect(delta.updated == ["b"])
        #expect(delta.deleted == ["x"])
    }

    @Test func emptyOnlyWithoutChangesAndWithHistory() {
        #expect(LibraryDelta().isEmpty)
        #expect(!LibraryDelta(updated: ["a"]).isEmpty)
        #expect(!LibraryDelta(fullRescanReason: .tokenExpired).isEmpty)
    }

    @Test(arguments: FullRescanReason.allCases)
    func fullDiffComparesCurrentWithCachedIDs(reason: FullRescanReason) {
        let delta = LibraryDelta.fullDiff(currentIDs: ["kept", "new"], cachedIDs: ["kept", "gone"], reason: reason)
        #expect(delta.inserted == ["new"])
        #expect(delta.deleted == ["gone"])
        #expect(delta.updated.isEmpty)
        #expect(delta.isFullRescanRequired)
        #expect(delta.fullRescanReason == reason)
    }
}
