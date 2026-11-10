import DataLayer
import Domain
import Foundation
import Testing

struct FileClusterRepositoryTests {
    private static func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "FileClusterRepositoryTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private static func result(_ sessionID: String, digest: UInt64 = .max, key: String = "k1") -> StoredSessionResult {
        StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: sessionID,
                content: SessionFingerprint.Content(memberCount: 3, digest: digest)
            ),
            clusters: [
                SimilarityCluster(
                    assetIDs: ["\(sessionID)-a", "\(sessionID)-b"],
                    averageDistance: 0.25,
                    isExactDuplicate: true
                )
            ],
            resultsKey: key
        )
    }

    @Test func aMissingFileIsEmpty() async {
        let repository = FileClusterRepository(directory: Self.makeDirectory())
        #expect(await repository.storedResults().isEmpty)
    }

    /// Every field survives a new instance, including a digest above `Int64.max`.
    @Test func resultsSurviveANewInstance() async throws {
        let directory = Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stored = [Self.result("s1"), Self.result("s2", digest: 42, key: "k2")]
        try await FileClusterRepository(directory: directory).apply(upserted: stored, removedSessionIDs: [])

        let reopened = await FileClusterRepository(directory: directory).storedResults()
        #expect(Set(reopened) == Set(stored))
    }

    @Test func applyReplacesAndRemoves() async throws {
        let directory = Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileClusterRepository(directory: directory)
        try await repository.apply(upserted: [Self.result("s1"), Self.result("s2")], removedSessionIDs: [])
        let replacement = Self.result("s1", digest: 7)
        try await repository.apply(upserted: [replacement], removedSessionIDs: ["s2", "unknown"])

        #expect(await repository.storedResults() == [replacement])
        #expect(await FileClusterRepository(directory: directory).storedResults() == [replacement])
    }

    @Test func anIDBothUpsertedAndRemovedIsStored() async throws {
        let directory = Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileClusterRepository(directory: directory)
        try await repository.apply(upserted: [Self.result("s1")], removedSessionIDs: ["s1"])
        #expect(await repository.storedResults().map(\.sessionID) == ["s1"])
    }

    @Test func anUnreadableFileIsEmptyAndGetsReplaced() async throws {
        let directory = Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: FileClusterRepository.fileName))

        let repository = FileClusterRepository(directory: directory)
        #expect(await repository.storedResults().isEmpty)
        try await repository.apply(upserted: [Self.result("s1")], removedSessionIDs: [])
        #expect(await FileClusterRepository(directory: directory).storedResults().count == 1)
    }

    @Test func theDirectoryIsExcludedFromBackup() async throws {
        let directory = Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileClusterRepository(directory: directory)
        try await repository.apply(upserted: [Self.result("s1")], removedSessionIDs: [])
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
