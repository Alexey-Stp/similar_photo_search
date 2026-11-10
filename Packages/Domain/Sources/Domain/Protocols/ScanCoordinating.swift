import Foundation

/// Runs library scans: finds groups of similar photos session by session and publishes them while it scans.
public protocol ScanCoordinating: Sendable {
    /// Starts a scan of `scope`, cancelling a scan that is still running (the new one waits until the old one has
    /// stopped and saved its results).
    ///
    /// - Parameters:
    ///   - scope: The photos to scan (`ScopePreferences.scanScope(now:calendar:)`).
    ///   - sessionConfig: How photos are cut into sessions (`ScopePreferences.sessionConfig`).
    /// - Returns: The progress and group streams of the new scan.
    func start(scope: ScanScope, sessionConfig: SessionConfig) async -> ScanStreams

    /// Stops the running scan. Results published so far stay saved; does nothing if no scan runs.
    func cancel() async

    /// Photos the user deleted while the scan runs: they are never loaded, analysed or published by it again.
    func excludeDeleted(_ assetIDs: Set<String>) async
}
