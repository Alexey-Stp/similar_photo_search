import Domain
import DomainTestSupport
import Foundation
import Testing

/// The incremental-scan rules at the Domain level: the real `SessionSegmenter` cuts the library before and after a
/// change, and `SessionChangePlanner` decides which sessions keep their results.
struct SessionChangePlannerTests {
    private static let revision = 2
    private static let modified = Date(timeIntervalSince1970: 1_700_000_000)

    /// A dated photo on November `day`, 2026 (UTC), with a modification date and favorite flag.
    private static func asset(
        _ id: String,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        modified: Date = modified,
        favorite: Bool = false
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: SessionSegmenterTests.date(day, hour, minute),
            modificationDate: modified,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: favorite,
            mediaSubtypes: []
        )
    }

    /// The sessions of `library` under the default 15-minute gap, newest first.
    private static func sessions(_ library: [PhotoAsset]) async throws -> [PhotoSession] {
        try await SessionSegmenterTests.events(library).sessions
    }

    /// The outcome of `plan(before:after:delta:)`.
    private struct Plan {
        /// The classification of each current session, keyed by its photo IDs in library order.
        let changes: [[String]: SessionChange]
        /// Previous session IDs whose results are out of date.
        let stale: Set<String>
        /// The previous scan's sessions.
        let before: [PhotoSession]
    }

    /// Classifies every session of `after` against the sessions of `before`.
    private static func plan(
        before: [PhotoAsset],
        after: [PhotoAsset],
        delta: LibraryDelta
    ) async throws -> Plan {
        let previous = try await sessions(before)
        var planner = SessionChangePlanner(previous: previous.map(SessionFingerprint.init), delta: delta)
        var changes: [[String]: SessionChange] = [:]
        for session in try await sessions(after) {
            changes[session.assets.map(\.id)] = planner.classify(session)
        }
        return Plan(changes: changes, stale: planner.staleSessionIDs, before: previous)
    }

    /// The analyzed record of `asset`, valid for its current modification date.
    private static func record(_ asset: PhotoAsset) -> AnalysisRecord {
        AnalysisRecord(
            featurePrint: FeaturePrint(
                assetID: asset.id,
                revision: revision,
                vector: [1, 0],
                assetModificationDate: asset.modificationDate
            ),
            analyzedAt: modified
        )
    }

    // Three sessions on two days: A (morning), B (afternoon), C (next day).
    private static let morning1 = asset("a1", 9, 10, 0)
    private static let morning2 = asset("a2", 9, 10, 5)
    private static let afternoon1 = asset("b1", 9, 14, 0)
    private static let afternoon2 = asset("b2", 9, 14, 5)
    private static let nextDay1 = asset("c1", 10, 9, 0)
    private static let nextDay2 = asset("c2", 10, 9, 5)
    private static let library = [morning1, morning2, afternoon1, afternoon2, nextDay1, nextDay2]

    // MARK: - New photos

    /// A new photo changes only its own session; the other sessions keep their results.
    @Test func newPhotoChangesOnlyItsOwnSession() async throws {
        let new = Self.asset("new", 9, 14, 10)
        let result = try await Self.plan(
            before: Self.library,
            after: Self.library + [new],
            delta: LibraryDelta(inserted: ["new"])
        )
        #expect(result.changes == [
            ["c2", "c1"]: .unchanged,
            ["new", "b2", "b1"]: .changed,
            ["a2", "a1"]: .unchanged
        ])
        let oldB = try #require(result.before.first(where: { $0.assets.map(\.id) == ["b2", "b1"] }))
        #expect(result.stale == [oldB.id])
    }

    /// An older photo joining keeps the session ID (it names the newest photo), but the membership differs.
    @Test func olderPhotoJoiningKeepsTheIDButStillChangesTheSession() async throws {
        let older = Self.asset("older", 9, 13, 55)
        let result = try await Self.plan(
            before: Self.library,
            after: Self.library + [older],
            delta: LibraryDelta(inserted: ["older"])
        )
        #expect(result.changes[["b2", "b1", "older"]] == .changed)
        let oldB = try #require(result.before.first(where: { $0.assets.map(\.id) == ["b2", "b1"] }))
        #expect(result.stale == [oldB.id])
    }

    /// Edge case: a new photo turns a single-photo session into a pair; the old photo is analysed for the first time.
    @Test func newPhotoTurnsASinglePhotoSessionIntoAPair() async throws {
        let single = Self.asset("single", 9, 18, 0)
        let new = Self.asset("new", 9, 18, 5)
        let before = Self.library + [single]
        let result = try await Self.plan(before: before, after: before + [new], delta: LibraryDelta(inserted: ["new"]))

        #expect(result.changes[["new", "single"]] == .changed)
        #expect(result.changes.values.filter { $0 == .changed }.count == 1)

        // The previous scan analysed only the sessions with two or more photos.
        let cache = MockFeaturePrintCache(entries: Self.library.map(Self.record))
        let afterSessions = try await Self.sessions(before + [new])
        let pair = try #require(afterSessions.first(where: { $0.assets.map(\.id) == ["new", "single"] }))
        #expect(pair.needsAnalysis)
        #expect(await cache.validEntries(for: pair.assets, revision: Self.revision).isEmpty,
                "Both photos of the new pair need Vision, the old one for the first time")
    }

    /// Edge case: a new photo closes the gap between two sessions, which merge and are clustered together.
    @Test func newPhotoBetweenTwoSessionsMergesThem() async throws {
        let early1 = Self.asset("x1", 11, 10, 0)
        let early2 = Self.asset("x2", 11, 10, 5)
        let late1 = Self.asset("y1", 11, 10, 25)
        let late2 = Self.asset("y2", 11, 10, 30)
        let bridge = Self.asset("bridge", 11, 10, 15)
        let before = Self.library + [early1, early2, late1, late2]
        let result = try await Self.plan(
            before: before,
            after: before + [bridge],
            delta: LibraryDelta(inserted: ["bridge"])
        )

        #expect(result.changes[["y2", "y1", "bridge", "x2", "x1"]] == .changed)
        #expect(result.changes.values.filter { $0 == .changed }.count == 1)
        let oldIDs = result.before.filter { ["x1", "y1"].contains($0.assets.last?.id) }.map(\.id)
        #expect(oldIDs.count == 2)
        #expect(result.stale == Set(oldIDs))

        // Cached members keep their prints; only the new photo needs Vision.
        let cache = MockFeaturePrintCache(entries: before.map(Self.record))
        let afterSessions = try await Self.sessions(before + [bridge])
        let merged = try #require(afterSessions.first(where: { $0.assets.count == 5 }))
        let hits = await cache.validEntries(for: merged.assets, revision: Self.revision)
        #expect(Set(hits.keys) == ["x1", "x2", "y1", "y2"])
    }

    // MARK: - Edits and deletions

    /// An edited photo changes its session, and its cached print misses on the new modification date.
    @Test func editedPhotoChangesItsSessionAndInvalidatesItsPrint() async throws {
        let edited = Self.asset("b1", 9, 14, 0, modified: Self.modified.addingTimeInterval(60))
        let after = Self.library.filter { $0.id != "b1" } + [edited]
        let result = try await Self.plan(before: Self.library, after: after, delta: LibraryDelta(updated: ["b1"]))
        #expect(result.changes[["b2", "b1"]] == .changed)
        #expect(result.changes.values.filter { $0 == .changed }.count == 1)

        let cache = MockFeaturePrintCache(entries: Self.library.map(Self.record))
        let hits = await cache.validEntries(for: [edited, Self.afternoon2], revision: Self.revision)
        #expect(Set(hits.keys) == ["b2"], "The edited photo's cached print no longer matches")
    }

    /// An update without a new modification date (for example on some metadata changes) still re-clusters the session.
    @Test func updateWithTheSameModificationDateStillChangesTheSession() async throws {
        let result = try await Self.plan(
            before: Self.library,
            after: Self.library,
            delta: LibraryDelta(updated: ["c1"])
        )
        #expect(result.changes[["c2", "c1"]] == .changed)
        #expect(result.changes[["a2", "a1"]] == .unchanged)
    }

    /// Deleting a photo changes the rest of its session and makes the old session stale.
    @Test func deletionChangesTheRestOfTheSession() async throws {
        let morning3 = Self.asset("a3", 9, 10, 10)
        let before = Self.library + [morning3]
        let after = before.filter { $0.id != "a2" }
        let result = try await Self.plan(before: before, after: after, delta: LibraryDelta(deleted: ["a2"]))
        #expect(result.changes[["a3", "a1"]] == .changed)
        #expect(result.stale.count == 1)
    }

    /// With no changes every session is reused and nothing is stale.
    @Test func unchangedLibraryReusesEverything() async throws {
        let result = try await Self.plan(before: Self.library, after: Self.library, delta: LibraryDelta())
        #expect(result.changes.values.allSatisfy { $0 == .unchanged })
        #expect(result.stale.isEmpty)
    }

    /// Without stored fingerprints (first scan, new session config) every session is changed.
    @Test func withoutPreviousFingerprintsEverySessionChanges() async throws {
        var planner = SessionChangePlanner(previous: [], delta: LibraryDelta())
        for session in try await Self.sessions(Self.library) {
            #expect(planner.classify(session) == .changed)
        }
        #expect(planner.staleSessionIDs.isEmpty)
    }

    // MARK: - Full rescan

    /// A full diff lists every uncached photo as inserted; only the fingerprints decide.
    @Test func fullRescanComparesFingerprintsOnly() async throws {
        let edited = Self.asset("c1", 10, 9, 0, modified: Self.modified.addingTimeInterval(60))
        let after = Self.library.filter { $0.id != "c1" } + [edited]
        let delta = LibraryDelta.fullDiff(
            currentIDs: Set(after.map(\.id)),
            cachedIDs: [],
            reason: .tokenExpired
        )
        let result = try await Self.plan(before: Self.library, after: after, delta: delta)
        #expect(result.changes == [
            ["c2", "c1"]: .changed,
            ["b2", "b1"]: .unchanged,
            ["a2", "a1"]: .unchanged
        ])
    }

    /// A favorite flag change alone changes the session, also on a full rescan.
    @Test func favoriteFlagIsPartOfTheFingerprint() async throws {
        let favorite = Self.asset("a1", 9, 10, 0, favorite: true)
        let after = Self.library.filter { $0.id != "a1" } + [favorite]
        let delta = LibraryDelta.fullDiff(currentIDs: [], cachedIDs: [], reason: .detailsUnavailable)
        let result = try await Self.plan(before: Self.library, after: after, delta: delta)
        #expect(result.changes[["a2", "a1"]] == .changed)
    }
}

struct SessionFingerprintTests {
    /// A session of `assets`, sorted into library order.
    private static func session(_ assets: [PhotoAsset]) throws -> PhotoSession {
        try #require(PhotoSession(assets: assets.sorted(by: PhotoAsset.libraryOrder)))
    }

    /// A photo at a fixed date, modified `modified` seconds after 1970 (`nil` for no date).
    private static func asset(_ id: String, modified: Double? = 1, favorite: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: 1_000),
            modificationDate: modified.map(Date.init(timeIntervalSince1970:)),
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: favorite,
            mediaSubtypes: []
        )
    }

    /// The same photos give the same fingerprint, whatever order they are passed in.
    @Test func sameMembersGiveTheSameFingerprint() throws {
        let lhs = SessionFingerprint(try Self.session([Self.asset("a"), Self.asset("b")]))
        let rhs = SessionFingerprint(try Self.session([Self.asset("b"), Self.asset("a")]))
        #expect(lhs == rhs)
        #expect(lhs.content.memberCount == 2)
    }

    /// Any change of member, modification date or favorite flag changes the content.
    @Test func anyMemberChangeChangesTheContent() throws {
        let base = SessionFingerprint(try Self.session([Self.asset("a"), Self.asset("b")])).content
        let variants: [[PhotoAsset]] = [
            [Self.asset("a"), Self.asset("c")],
            [Self.asset("a"), Self.asset("b"), Self.asset("c")],
            [Self.asset("a")],
            [Self.asset("a"), Self.asset("b", modified: 2)],
            // Less than half a millisecond apart: still a different modification date for the cache.
            [Self.asset("a"), Self.asset("b", modified: 1.000_1)],
            [Self.asset("a"), Self.asset("b", modified: nil)],
            [Self.asset("a"), Self.asset("b", favorite: true)],
            // Concatenated IDs that read the same must still differ.
            [Self.asset("ab"), Self.asset("")]
        ]
        for variant in variants {
            #expect(SessionFingerprint(try Self.session(variant)).content != base)
        }
    }

    /// A fingerprint survives JSON encoding, so it can be stored.
    @Test func roundTripsThroughCodable() throws {
        let fingerprint = SessionFingerprint(try Self.session([Self.asset("a")]))
        let decoded = try JSONDecoder().decode(SessionFingerprint.self, from: JSONEncoder().encode(fingerprint))
        #expect(decoded == fingerprint)
    }
}
