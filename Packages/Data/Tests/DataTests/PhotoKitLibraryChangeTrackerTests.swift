@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing

/// The tracker's token handling and fallbacks, over a scripted `PersistentChangeSource` and a temporary token file.
struct PhotoKitLibraryChangeTrackerTests {
    /// A scripted source that records the order of calls.
    final class FakeSource: PersistentChangeSource, @unchecked Sendable {
        // @unchecked: tests drive it from one task at a time.
        var token = Data("token-1".utf8)
        var changes: Result<LibraryDelta, any Error> = .success(LibraryDelta())
        var currentIDs: Set<String> = ["a", "b"]
        private(set) var calls: [String] = []
        private(set) var changesRequestedSince: [Data] = []

        /// Records the call and returns `token`.
        func currentToken() -> Data? {
            calls.append("currentToken")
            return token
        }

        /// Records the call and its token, then returns or throws `changes`.
        func assetChanges(since token: Data) throws -> LibraryDelta {
            calls.append("assetChanges")
            changesRequestedSince.append(token)
            return try changes.get()
        }

        /// Records the call and returns `currentIDs`.
        func allAssetIDs() throws -> Set<String> {
            calls.append("allAssetIDs")
            return currentIDs
        }
    }

    /// A tracker over `source` whose token file lives in a fresh temporary directory, removed afterwards.
    private func withTracker(
        _ source: FakeSource,
        _ body: (PhotoKitLibraryChangeTracker, ChangeTokenStore) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChangeTrackerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChangeTokenStore(directory: directory)
        try await body(PhotoKitLibraryChangeTracker(source: source, tokenStore: store), store)
    }

    /// Without a saved token the first scan is a `noBaseline` full diff; the token is read before the library.
    @Test func firstScanHasNoBaselineAndListsTheLibrary() async throws {
        let source = FakeSource()
        try await withTracker(source) { tracker, _ in
            let report = try await tracker.changesSinceLastScan()
            #expect(report == .historyUnavailable(.noBaseline, currentAssetIDs: ["a", "b"]))
            #expect(source.calls == ["currentToken", "allAssetIDs"], "The token is read before the library")
        }
    }

    /// The start token is saved, not the one current when the scan ends: changes made during the scan come again.
    @Test func commitSavesTheTokenReadAtTheStart() async throws {
        let source = FakeSource()
        try await withTracker(source) { tracker, store in
            _ = try await tracker.changesSinceLastScan()
            source.token = Data("token-2-during-scan".utf8)
            try await tracker.commitScanCompleted()
            #expect(store.load() == Data("token-1".utf8))

            source.changes = .success(LibraryDelta(inserted: ["new"], deleted: ["gone"]))
            let report = try await tracker.changesSinceLastScan()
            #expect(report == .changes(LibraryDelta(inserted: ["new"], deleted: ["gone"])))
            #expect(source.changesRequestedSince == [Data("token-1".utf8)])
            #expect(source.calls.suffix(2) == ["currentToken", "assetChanges"])
        }
    }

    /// A scan that never commits leaves the saved token alone, so the next scan sees the same changes.
    @Test func withoutCommitTheNextScanStartsFromTheSameBaseline() async throws {
        let source = FakeSource()
        try await withTracker(source) { tracker, store in
            try store.save(Data("baseline".utf8))
            _ = try await tracker.changesSinceLastScan()
            // The scan was cancelled: no commit.
            source.token = Data("later".utf8)
            _ = try await tracker.changesSinceLastScan()
            #expect(source.changesRequestedSince == [Data("baseline".utf8), Data("baseline".utf8)])
            #expect(store.load() == Data("baseline".utf8))
        }
    }

    /// Committing before any scan started writes nothing.
    @Test func commitWithoutAStartedScanDoesNothing() async throws {
        try await withTracker(FakeSource()) { tracker, store in
            try await tracker.commitScanCompleted()
            #expect(store.load() == nil)
        }
    }

    /// A start token is saved by one commit only; a second commit does not overwrite a newer token.
    @Test func commitIsUsedOnlyOnce() async throws {
        let source = FakeSource()
        try await withTracker(source) { tracker, store in
            _ = try await tracker.changesSinceLastScan()
            try await tracker.commitScanCompleted()
            try store.save(Data("other".utf8))
            try await tracker.commitScanCompleted()
            #expect(store.load() == Data("other".utf8))
        }
    }

    /// Every history error becomes a full-library fallback with the matching reason.
    @Test(arguments: [
        (PersistentChangeError.tokenExpired, FullRescanReason.tokenExpired),
        (.detailsUnavailable, .detailsUnavailable),
        (.unreadableToken, .historyUnreadable),
        (.other, .historyUnreadable)
    ])
    func historyErrorsFallBackToTheFullLibrary(error: PersistentChangeError, reason: FullRescanReason) async throws {
        let source = FakeSource()
        source.changes = .failure(error)
        try await withTracker(source) { tracker, store in
            try store.save(Data("old".utf8))
            let report = try await tracker.changesSinceLastScan()
            #expect(report == .historyUnavailable(reason, currentAssetIDs: ["a", "b"]))
        }
    }

    /// An already-cancelled scan throws before reading the token or listing the library.
    @Test func cancelledTaskTouchesNothing() async throws {
        let source = FakeSource()
        source.currentIDs = []
        try await withTracker(source) { tracker, _ in
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await tracker.changesSinceLastScan()
            }
            await #expect(throws: CancellationError.self) {
                _ = try await task.value
            }
            #expect(source.calls.isEmpty)
        }
    }

    /// Cancellation while reading the history is thrown, not turned into a full diff.
    @Test func cancellationIsNotAFallback() async throws {
        let source = FakeSource()
        source.changes = .failure(CancellationError())
        try await withTracker(source) { tracker, store in
            try store.save(Data("old".utf8))
            await #expect(throws: CancellationError.self) {
                _ = try await tracker.changesSinceLastScan()
            }
        }
    }

    // MARK: - PhotoKit error mapping

    /// PhotoKit error codes map to their fallback; other codes and domains map to `.other`.
    @Test func photoKitErrorsMapToTheirFallbackReason() {
        let expired = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.Code.persistentChangeTokenExpired.rawValue
        )
        let truncated = NSError(
            domain: PHPhotosErrorDomain,
            code: PHPhotosError.Code.persistentChangeDetailsUnavailable.rawValue
        )
        let otherPhotoKit = NSError(domain: PHPhotosErrorDomain, code: PHPhotosError.Code.accessRestricted.rawValue)
        let unrelated = NSError(
            domain: NSCocoaErrorDomain,
            code: PHPhotosError.Code.persistentChangeTokenExpired.rawValue
        )

        #expect(PhotoKitPersistentChangeSource.map(expired) == .tokenExpired)
        #expect(PhotoKitPersistentChangeSource.map(PHPhotosError(.persistentChangeTokenExpired)) == .tokenExpired)
        #expect(PhotoKitPersistentChangeSource.map(truncated) == .detailsUnavailable)
        #expect(PhotoKitPersistentChangeSource.map(otherPhotoKit) == .other)
        #expect(PhotoKitPersistentChangeSource.map(unrelated) == .other)
    }

    /// A token that is not an archive is reported as unreadable.
    @Test func garbageTokenIsUnreadable() {
        #expect(throws: PersistentChangeError.unreadableToken) {
            _ = try PhotoKitPersistentChangeSource().assetChanges(since: Data("not an archive".utf8))
        }
    }

    // MARK: - Token file

    /// The token round-trips through its file, the directory is excluded from backup, `remove()` deletes it.
    @Test func tokenFileIsExcludedFromBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ChangeTokenStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChangeTokenStore(directory: directory)
        #expect(store.load() == nil)
        try store.save(Data("t".utf8))
        #expect(store.load() == Data("t".utf8))
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        store.remove()
        #expect(store.load() == nil)
    }
}
