import Domain
import Foundation

/// `ScanCoordinating` whose streams tests feed by hand.
public actor MockScanCoordinator: ScanCoordinating {
    /// Every `start` call, in order.
    public private(set) var startCalls: [(scope: ScanScope, sessionConfig: SessionConfig)] = []
    /// How many times `cancel()` was called.
    public private(set) var cancelCallCount = 0
    /// Every set passed to `excludeDeleted`, in order.
    public private(set) var excludedIDs: [Set<String>] = []

    private var progressContinuation: AsyncStream<ScanProgress>.Continuation?
    private var clusterContinuation: AsyncStream<ClusterUpdate>.Continuation?
    /// When `true`, `cancel()` ends the streams like a real scan (`.cancelled`, then `.finished`).
    private let finishesOnCancel: Bool

    /// Creates the mock.
    public init(finishesOnCancel: Bool = true) {
        self.finishesOnCancel = finishesOnCancel
    }

    /// Records the call and returns fresh streams that `send` feeds.
    public func start(scope: ScanScope, sessionConfig: SessionConfig) -> ScanStreams {
        startCalls.append((scope, sessionConfig))
        progressContinuation?.finish()
        clusterContinuation?.finish()
        let (progress, progressContinuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let (clusters, clusterContinuation) = AsyncStream.makeStream(of: ClusterUpdate.self)
        self.progressContinuation = progressContinuation
        self.clusterContinuation = clusterContinuation
        return ScanStreams(progress: progress, clusters: clusters)
    }

    /// Counts the call; ends the streams with `.cancelled` if `finishesOnCancel`.
    public func cancel() {
        cancelCallCount += 1
        guard finishesOnCancel else { return }
        send(ScanProgress(phase: .cancelled))
        finish()
    }

    /// Records the IDs.
    public func excludeDeleted(_ assetIDs: Set<String>) {
        excludedIDs.append(assetIDs)
    }

    /// Publishes a progress snapshot on the current scan.
    public func send(_ progress: ScanProgress) {
        progressContinuation?.yield(progress)
    }

    /// Publishes a group change on the current scan.
    public func send(_ update: ClusterUpdate) {
        clusterContinuation?.yield(update)
    }

    /// Ends the current scan's streams (`.finished` first).
    public func finish() {
        clusterContinuation?.yield(.finished)
        clusterContinuation?.finish()
        progressContinuation?.finish()
        clusterContinuation = nil
        progressContinuation = nil
    }
}
