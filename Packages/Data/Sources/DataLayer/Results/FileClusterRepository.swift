import Domain
import Foundation
import os

/// `ClusterRepository` in one small JSON file: the clusters of analysed sessions with their fingerprints.
///
/// The results are asset IDs only (a few hundred KB for a large library), so they are kept in memory after the first
/// read and the whole file is rewritten atomically on every `apply`; the coordinator batches its writes. The file
/// lives in Application Support/Results, excluded from backup like the analysis cache (results restored next to
/// an empty cache, or onto another device's library, would be wrong), and gets
/// `.completeFileProtectionUntilFirstUserAuthentication`. Only file contents are read, never file dates.
public actor FileClusterRepository: ClusterRepository {
    /// Name of the directory inside Application Support.
    public static let directoryName = "Results"
    /// Name of the results file.
    public static let fileName = "Clusters.json"
    /// Format version of the file. A file of another version is ignored (rebuilt by the next scan).
    static let formatVersion = 1

    private static let logger = Logger(subsystem: "com.similarphotos", category: "clusterResults")

    /// The directory holding the file.
    public let directory: URL
    private var cache: [String: StoredSessionResult]?

    /// Application Support/Results.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// A repository whose file lives in `directory`.
    public init(directory: URL = FileClusterRepository.defaultDirectory) {
        self.directory = directory
    }

    private var fileURL: URL {
        directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// Every stored result; empty if the file is missing or unreadable.
    public func storedResults() -> [StoredSessionResult] {
        Array(loaded().values)
    }

    /// Applies the changes and rewrites the file.
    public func apply(upserted: [StoredSessionResult], removedSessionIDs: Set<String>) throws {
        var results = loaded()
        for id in removedSessionIDs {
            results[id] = nil
        }
        for result in upserted {
            results[result.sessionID] = result
        }
        try write(results)
        cache = results
    }

    // MARK: - File

    /// The results in memory, read from the file on first use.
    private func loaded() -> [String: StoredSessionResult] {
        if let cache { return cache }
        let results = read()
        cache = results
        return results
    }

    /// Decodes the file; a missing, unreadable or other-version file gives no results.
    private func read() -> [String: StoredSessionResult] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        do {
            let file = try JSONDecoder().decode(ResultsFile.self, from: data)
            guard file.version == Self.formatVersion else { return [:] }
            return Dictionary(
                file.sessions.map { ($0.sessionID, $0.domain) },
                uniquingKeysWith: { _, last in last }
            )
        } catch {
            Self.logger.error("""
                Cluster results unreadable, starting empty: \(String(describing: error), privacy: .private)
                """)
            return [:]
        }
    }

    /// Rewrites the file atomically, creating the directory and excluding it from backup first.
    private func write(_ results: [String: StoredSessionResult]) throws {
        let sessions = results.values
            .sorted { $0.sessionID < $1.sessionID }
            .map(StoredSessionDTO.init)
        let data = try JSONEncoder().encode(ResultsFile(version: Self.formatVersion, sessions: sessions))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - File format

private struct ResultsFile: Codable {
    let version: Int
    let sessions: [StoredSessionDTO]
}

private struct StoredSessionDTO: Codable {
    let sessionID: String
    let memberCount: Int
    /// `SessionFingerprint.Content.digest` as its bit pattern, so every JSON reader keeps all 64 bits.
    let digest: Int64
    let resultsKey: String
    let clusters: [ClusterDTO]

    /// The file form of a stored result.
    init(_ result: StoredSessionResult) {
        sessionID = result.sessionID
        memberCount = result.fingerprint.content.memberCount
        digest = Int64(bitPattern: result.fingerprint.content.digest)
        resultsKey = result.resultsKey
        clusters = result.clusters.map(ClusterDTO.init)
    }

    var domain: StoredSessionResult {
        StoredSessionResult(
            fingerprint: SessionFingerprint(
                sessionID: sessionID,
                content: SessionFingerprint.Content(memberCount: memberCount, digest: UInt64(bitPattern: digest))
            ),
            clusters: clusters.map(\.domain),
            resultsKey: resultsKey
        )
    }
}

private struct ClusterDTO: Codable {
    let id: String
    let assetIDs: [String]
    let averageDistance: Float
    let isExactDuplicate: Bool

    /// The file form of a cluster (without a keeper, which is never stored).
    init(_ cluster: SimilarityCluster) {
        id = cluster.id
        assetIDs = cluster.assetIDs
        averageDistance = cluster.averageDistance
        isExactDuplicate = cluster.isExactDuplicate
    }

    var domain: SimilarityCluster {
        SimilarityCluster(
            id: id,
            assetIDs: assetIDs,
            averageDistance: averageDistance,
            isExactDuplicate: isExactDuplicate
        )
    }
}
