import Foundation

/// Persists the clusters of analysed sessions together with their `SessionFingerprint`s, so a later scan reuses the
/// clusters of unchanged sessions and the home screen can show the last results at launch.
///
/// Small: it holds asset IDs, never vectors or images.
public protocol ClusterRepository: Sendable {
    /// Every stored session result, of any `resultsKey`. Never throws: an unreadable store is empty.
    func storedResults() async -> [StoredSessionResult]

    /// Stores `upserted` (replacing results with the same session ID) and removes the results of
    /// `removedSessionIDs`, in one write. A session ID in both is stored.
    func apply(upserted: [StoredSessionResult], removedSessionIDs: Set<String>) async throws
}
