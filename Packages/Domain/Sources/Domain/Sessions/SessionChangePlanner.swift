import Foundation

/// Whether a session's stored results from the previous scan can be reused.
public enum SessionChange: Sendable, Hashable {
    /// Same photos, unchanged, as a session of the previous scan: reuse its clusters, nothing to analyse.
    case unchanged
    /// New, grown, shrunk, merged, split or edited: cluster it again. Its photos still go through the feature-print
    /// cache first, so only photos without a valid record reach Vision (for example the older photo of a
    /// single-photo session that a new photo turned into a pair).
    case changed
}

/// Decides, session by session, which results of the previous scan are still valid.
///
/// Feed it the sessions of the current scan as `SessionSegmenter` emits them (`classify(_:)`), then read
/// `staleSessionIDs` for the previous sessions whose stored results must be dropped.
///
/// A session is `.unchanged` only if a previous session had the same `SessionFingerprint.Content` and, for an
/// incremental delta, none of its photos is in `inserted` or `updated`. Membership is compared, not session IDs:
/// - a new photo between two sessions that closes the gap gives one merged session whose membership matches neither
///   old session, so it is `.changed` and both old sessions become stale;
/// - a new photo next to a single-photo session gives a pair that matches nothing, so it is `.changed`;
/// - a deleted photo changes its session's membership, so the rest of that session is `.changed`.
///
/// On a full rescan (`LibraryDelta.isFullRescanRequired`) `inserted` lists every uncached photo and `updated` is
/// empty, so only the fingerprints are compared; they include modification dates and favorite flags.
public struct SessionChangePlanner: Sendable {
    private var previousByContent: [SessionFingerprint.Content: String]
    private let changedIDs: Set<String>
    private var reusedSessionIDs: Set<String> = []
    private let previousSessionIDs: Set<String>

    /// Creates a planner.
    /// - Parameters:
    ///   - previous: The fingerprints stored with the previous scan's results. Pass none after the session config
    ///     changed: then every session is `.changed`.
    ///   - delta: The changes since the previous scan.
    public init(previous: some Sequence<SessionFingerprint>, delta: LibraryDelta) {
        var byContent: [SessionFingerprint.Content: String] = [:]
        var ids: Set<String> = []
        for fingerprint in previous {
            byContent[fingerprint.content] = fingerprint.sessionID
            ids.insert(fingerprint.sessionID)
        }
        self.previousByContent = byContent
        self.previousSessionIDs = ids
        self.changedIDs = delta.isFullRescanRequired ? [] : delta.inserted.union(delta.updated)
    }

    /// Classifies one session of the current scan. Each previous session can be reused by one current session only.
    public mutating func classify(_ session: PhotoSession) -> SessionChange {
        let content = SessionFingerprint(session).content
        guard let previousID = previousByContent[content],
              !session.assets.contains(where: { changedIDs.contains($0.id) }) else {
            return .changed
        }
        previousByContent[content] = nil
        reusedSessionIDs.insert(previousID)
        return .unchanged
    }

    /// The previous sessions not reused by any `.unchanged` session so far. After every current session has been
    /// classified, these are the sessions whose stored results are out of date (deleted, merged, grown or edited).
    public var staleSessionIDs: Set<String> {
        previousSessionIDs.subtracting(reusedSessionIDs)
    }
}
