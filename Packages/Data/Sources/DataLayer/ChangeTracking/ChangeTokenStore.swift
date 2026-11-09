import Foundation

/// Keeps the archived change token of the last completed scan in one small file.
///
/// The file lives in Application Support/ChangeTracking, which is excluded from backup like the analysis cache: a
/// token restored onto another device or next to an empty cache would describe a library that isn't there. Only
/// the file's contents are read, never its dates (no required-reason API).
struct ChangeTokenStore: Sendable {
    /// Name of the directory inside Application Support.
    static let directoryName = "ChangeTracking"
    /// Name of the token file.
    static let fileName = "LastScan.token"

    /// Application Support/ChangeTracking.
    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// The directory holding the token file.
    let directory: URL

    /// The token file.
    var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    /// A store in `directory`.
    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// The saved token, or `nil` if none was saved or the file can't be read.
    func load() -> Data? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        return data
    }

    /// Replaces the saved token atomically. Creates the directory and excludes it from backup first.
    func save(_ token: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        try token.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Deletes the saved token, so the next scan does a full diff.
    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
