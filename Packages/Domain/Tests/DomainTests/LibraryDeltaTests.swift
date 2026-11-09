import Domain
import Testing

struct LibraryDeltaTests {
    /// A photo inserted and then updated is still only inserted.
    @Test func insertedThenUpdatedStaysInserted() {
        var delta = LibraryDelta()
        delta.record(inserted: ["a"], updated: [], deleted: [])
        delta.record(inserted: [], updated: ["a", "b"], deleted: [])
        #expect(delta.inserted == ["a"])
        #expect(delta.updated == ["b"])
        #expect(delta.deleted.isEmpty)
    }

    /// A photo inserted or updated and then deleted is only deleted.
    @Test func deletedAfterInsertOrUpdateIsOnlyDeleted() {
        var delta = LibraryDelta()
        delta.record(inserted: ["a"], updated: ["b"], deleted: [])
        delta.record(inserted: [], updated: [], deleted: ["a", "b"])
        #expect(delta.inserted.isEmpty)
        #expect(delta.updated.isEmpty)
        #expect(delta.deleted == ["a", "b"])
    }

    /// A photo deleted and then inserted again is inserted.
    @Test func reinsertedAfterDeleteIsInserted() {
        var delta = LibraryDelta()
        delta.record(inserted: [], updated: [], deleted: ["a"])
        delta.record(inserted: ["a"], updated: [], deleted: [])
        #expect(delta.inserted == ["a"])
        #expect(delta.deleted.isEmpty)
    }

    /// The initializer removes overlaps between the three sets.
    @Test func initKeepsTheSetsDisjoint() {
        let delta = LibraryDelta(inserted: ["a", "x"], updated: ["a", "b"], deleted: ["x"])
        #expect(delta.inserted == ["a"])
        #expect(delta.updated == ["b"])
        #expect(delta.deleted == ["x"])
    }

    /// A delta is empty only with no changes and a usable history.
    @Test func emptyOnlyWithoutChangesAndWithHistory() {
        #expect(LibraryDelta().isEmpty)
        #expect(!LibraryDelta(updated: ["a"]).isEmpty)
        #expect(!LibraryDelta(fullRescanReason: .tokenExpired).isEmpty)
    }

    /// The full diff marks uncached photos inserted and cached-but-gone photos deleted.
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
