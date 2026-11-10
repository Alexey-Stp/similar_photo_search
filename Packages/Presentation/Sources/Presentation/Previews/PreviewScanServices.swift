#if DEBUG
import Domain
import Foundation

/// `ScanCoordinating` for SwiftUI previews: publishes one fixed snapshot and never finishes.
actor PreviewScanCoordinator: ScanCoordinating {
    private let snapshot: ScanProgress

    /// Creates a coordinator that shows `snapshot`.
    init(snapshot: ScanProgress) {
        self.snapshot = snapshot
    }

    /// Returns streams that publish the snapshot once.
    func start(scope: ScanScope, sessionConfig: SessionConfig) -> ScanStreams {
        let (progress, progressContinuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let (clusters, _) = AsyncStream.makeStream(of: ClusterUpdate.self)
        progressContinuation.yield(snapshot)
        return ScanStreams(progress: progress, clusters: clusters)
    }

    /// Does nothing.
    func cancel() {}

    /// Does nothing.
    func excludeDeleted(_ assetIDs: Set<String>) {}
}

/// Idle timer and background tasks that do nothing, for previews.
@MainActor
final class PreviewAppLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    /// Does nothing.
    func setIdleTimerDisabled(_ disabled: Bool) {}

    /// Grants no time.
    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        nil
    }

    /// Does nothing.
    func endBackgroundTask(_ token: BackgroundTaskToken) {}
}

extension ScanViewModel {
    /// A view model whose scan shows `snapshot` once started.
    static func preview(
        snapshot: ScanProgress = ScanProgress(processed: 3_120, total: 10_000, phase: .analyzing, eta: 140)
    ) -> ScanViewModel {
        let lifecycle = PreviewAppLifecycle()
        return ScanViewModel(
            coordinator: PreviewScanCoordinator(snapshot: snapshot),
            preferences: PreviewScopePreferencesStore(preferences: .default),
            selection: .preview(),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
    }
}
#endif
