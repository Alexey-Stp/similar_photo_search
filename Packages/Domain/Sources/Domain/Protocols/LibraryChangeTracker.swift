import Foundation

/// Finds what changed in the photo library since the last successful scan, from PhotoKit's persistent change history.
///
/// Protocol of a scan:
/// 1. `changesSinceLastScan()` first, before the library is enumerated. It remembers the library's current change
///    token as the start of this scan.
/// 2. Run the scan.
/// 3. `commitScanCompleted()` only if the scan succeeded. It saves the **start** token, so changes made while the
///    scan ran are reported again by the next scan instead of being lost. A cancelled or failed scan commits nothing
///    and the next scan sees the same changes again.
///
/// Must not be called before the user granted photo access.
public protocol LibraryChangeTracker: Sendable {
    /// The changes since the last committed scan, or the photos needed for a full diff if the history can't be used.
    ///
    /// Throws `CancellationError` if the task is cancelled. Every history problem (no baseline, expired token,
    /// truncated details, unreadable token) is reported as `.historyUnavailable`, not thrown.
    func changesSinceLastScan() async throws -> LibraryChangeReport

    /// Persists the token read by the last `changesSinceLastScan()`. Does nothing if there is none.
    func commitScanCompleted() async throws
}

/// Signals that the photo library changed while the app runs, for refreshing visible results.
public protocol LibraryChangeObserving: Sendable {
    /// A stream that yields once after a burst of library changes has settled (debounced). Each call returns a new
    /// stream; all streams receive every signal. The first call starts observing: call it only after the user
    /// granted photo access.
    func changes() -> AsyncStream<Void>
}
