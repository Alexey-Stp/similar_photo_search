import Foundation
import os
import SwiftData

/// Opens the analysis cache's `ModelContainer`, rebuilding the store if it can't be opened.
enum AnalysisContainerFactory {
    /// File name of the SQLite store inside the store directory. SQLite adds `-wal` and `-shm` next to it.
    static let storeFileName = "Analysis.store"
    /// Name of the store directory inside Application Support.
    static let directoryName = "Analysis"

    private static let logger = Logger(subsystem: "com.similarphotos", category: "analysisCache")

    /// The default store directory: Application Support/Analysis.
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// The store file inside `directory`.
    static func storeURL(in directory: URL) -> URL {
        directory.appending(path: storeFileName, directoryHint: .notDirectory)
    }

    /// A container for `location`, or `nil` if not even an in-memory store can be created.
    ///
    /// A file store that fails to open (corrupt file, failed migration) is deleted, together with its `-wal` and
    /// `-shm` files, and opened once more. If that fails too, the cache runs in memory for this launch: analysis
    /// still works, it just isn't remembered. Nothing here crashes the app.
    static func makeContainer(location: SwiftDataFeaturePrintCache.Location) -> ModelContainer? {
        let directory: URL
        switch location {
        case .inMemory:
            return makeInMemoryContainer()
        case .applicationSupport:
            directory = defaultDirectory
        case .directory(let url):
            directory = url
        }

        do {
            try prepareDirectory(directory)
        } catch {
            logger.error("Analysis cache directory unavailable: \(String(describing: error), privacy: .private)")
            return makeInMemoryContainer()
        }

        let url = storeURL(in: directory)
        do {
            let container = try makeFileContainer(url: url)
            protectStoreFiles(at: url)
            return container
        } catch {
            logger.error("""
                Analysis cache failed to open, deleting and rebuilding it: \
                \(String(describing: error), privacy: .private)
                """)
        }

        deleteStoreFiles(at: url)
        do {
            let container = try makeFileContainer(url: url)
            protectStoreFiles(at: url)
            return container
        } catch {
            logger.fault("""
                Analysis cache could not be rebuilt, keeping it in memory for this launch: \
                \(String(describing: error), privacy: .private)
                """)
            return makeInMemoryContainer()
        }
    }

    /// The store file and the SQLite side files that belong to it.
    static func storeFiles(at url: URL) -> [URL] {
        [url] + ["-wal", "-shm"].map { url.deletingLastPathComponent().appending(path: url.lastPathComponent + $0) }
    }

    // MARK: - Private

    /// The schema of the current version, `AnalysisSchemaV1`.
    private static var schema: Schema { Schema(versionedSchema: AnalysisSchemaV1.self) }

    /// A container over the SQLite store at `url`, with the migration plan and no CloudKit.
    private static func makeFileContainer(url: URL) throws -> ModelContainer {
        // `cloudKitDatabase: .none` explicitly: the default `.automatic` would sync through CloudKit if the app ever
        // gained an iCloud entitlement (CLAUDE.md rule 1).
        let configuration = ModelConfiguration(
            "Analysis",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AnalysisMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// A container that keeps nothing on disk, or `nil` if even that can't be created.
    private static func makeInMemoryContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(
            "Analysis-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AnalysisMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            logger.fault("Analysis cache unavailable: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// Creates the directory, excludes it (and so every file in it) from iCloud and device backups, and gives it the
    /// file protection that new files in it inherit.
    private static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        setProtection(of: directory)
    }

    /// Sets the file protection of the store files that exist, in case one was created before the directory had it.
    private static func protectStoreFiles(at url: URL) {
        for file in storeFiles(at: url) where FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            setProtection(of: file)
        }
    }

    /// `.completeUntilFirstUserAuthentication`: readable while the device is locked after the first unlock, so a
    /// background scan can use the cache.
    private static func setProtection(of url: URL) {
        #if os(iOS)
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        } catch {
            logger.error("Analysis cache file protection not set: \(String(describing: error), privacy: .private)")
        }
        #endif
    }

    /// Deletes the store file and its `-wal`/`-shm` files; a file that can't be deleted is logged.
    private static func deleteStoreFiles(at url: URL) {
        for file in storeFiles(at: url) where FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                logger.error("Analysis cache file not deleted: \(String(describing: error), privacy: .private)")
            }
        }
    }
}
