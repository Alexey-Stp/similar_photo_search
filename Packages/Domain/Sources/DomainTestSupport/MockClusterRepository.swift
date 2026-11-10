import Domain
import Foundation

/// In-memory `ClusterRepository` that records its writes.
public actor MockClusterRepository: ClusterRepository {
    /// Stored results by session ID.
    public private(set) var results: [String: StoredSessionResult]
    /// Every `apply` call, in order.
    public private(set) var applyCalls: [(upserted: [StoredSessionResult], removed: Set<String>)] = []
    /// When set, `apply` throws it and changes nothing.
    public private(set) var writeError: (any Error)?

    /// Creates the repository with some results already stored.
    public init(results: [StoredSessionResult] = []) {
        self.results = Dictionary(results.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Every stored result, ordered by session ID.
    public func storedResults() -> [StoredSessionResult] {
        results.values.sorted { $0.sessionID < $1.sessionID }
    }

    /// Records the call, removes, then stores (so an ID in both is stored).
    public func apply(upserted: [StoredSessionResult], removedSessionIDs: Set<String>) throws {
        if let writeError { throw writeError }
        applyCalls.append((upserted, removedSessionIDs))
        for id in removedSessionIDs {
            results[id] = nil
        }
        for result in upserted {
            results[result.sessionID] = result
        }
    }

    /// Sets or clears the write error.
    public func setWriteError(_ error: (any Error)?) {
        writeError = error
    }
}
