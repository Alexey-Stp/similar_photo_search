import Foundation

/// One scan of `AnalysisCoordinator`: owns the progress state, the throttling state and the two stream
/// continuations. Sessions are processed one after another (so groups are published in session order); the image
/// work inside a session runs in child tasks with a bounded width.
actor ScanRun {
    let deps: AnalysisCoordinator.Dependencies
    let scope: ScanScope
    let sessionConfig: SessionConfig
    let exclusions: ExclusionSet
    let progressContinuation: AsyncStream<ScanProgress>.Continuation
    let clusterContinuation: AsyncStream<ClusterUpdate>.Continuation
    let revision: Int
    let scoringVersion: Int

    // Progress.
    var progress = ScanProgress()
    var throttle: ScanProgressThrottle
    var analysisStartedAt: Date

    // Throttling.
    var pauseWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    var nextWaiterID: UInt64 = 0

    // Results.
    var publishedClusterIDs: Set<String> = []
    var writtenSessionIDs: Set<String> = []
    var pendingUpserts: [StoredSessionResult] = []
    var pendingRemovals: Set<String> = []
    var sessionsSinceFlush = 0

    /// Creates a run; nothing happens until `execute()`.
    init(
        dependencies: AnalysisCoordinator.Dependencies,
        scope: ScanScope,
        sessionConfig: SessionConfig,
        exclusions: ExclusionSet,
        progress: AsyncStream<ScanProgress>.Continuation,
        clusters: AsyncStream<ClusterUpdate>.Continuation
    ) {
        self.deps = dependencies
        self.scope = scope
        self.sessionConfig = sessionConfig
        self.exclusions = exclusions
        self.progressContinuation = progress
        self.clusterContinuation = clusters
        self.revision = dependencies.featurePrints.revision
        self.scoringVersion = dependencies.qualityScorer.scoringVersion
        self.throttle = ScanProgressThrottle(interval: dependencies.settings.progressInterval)
        self.analysisStartedAt = dependencies.now()
    }

    // MARK: - Lifecycle

    /// Runs the scan to its end and finishes both streams.
    func execute() async {
        let changes = deps.thermalMonitor.conditionChanges()
        let watcher = Task { [weak self] in
            for await conditions in changes {
                await self?.conditionsChanged(conditions)
            }
        }
        defer { watcher.cancel() }
        progress.conditions = await deps.thermalMonitor.currentConditions()

        let finalPhase: ScanPhase
        do {
            try Task.checkCancellation()
            try await scan()
            finalPhase = .done
        } catch let failure as ScanFailure {
            finalPhase = Task.isCancelled ? .cancelled : .failed(failure)
        } catch {
            finalPhase = Task.isCancelled || error is CancellationError ? .cancelled : .failed(.libraryUnavailable)
        }
        if finalPhase != .done {
            await flushResults()
        }
        resumeAllPauseWaiters(throwing: CancellationError())
        progress.phase = finalPhase
        progress.eta = finalPhase == .done ? 0 : nil
        if finalPhase == .done {
            progress.total = progress.processed
        }
        report(force: true)
        clusterContinuation.yield(.finished)
        clusterContinuation.finish()
        progressContinuation.finish()
    }

    /// The scan itself; throws `CancellationError`, `ScanFailure` or a library error.
    /// The scan itself; throws `CancellationError`, `ScanFailure` or a library error.
    func scan() async throws {
        report(force: true)
        progress.total = await deps.library.assetCount(scope: scope)
        try Task.checkCancellation()
        let (delta, canCommit) = try await prepareDelta()
        let stored = await deps.results.storedResults()
        try Task.checkCancellation()
        let context = makeContext(stored: stored, delta: delta)

        analysisStartedAt = deps.now()
        progress.phase = .analyzing
        report(force: true)

        let sessions = deps.segmenter.sessions(
            from: deps.library.assetPages(scope: scope, pageSize: deps.settings.pageSize),
            config: sessionConfig
        )
        var iterator = sessions.makeAsyncIterator()
        while let event = try await iterator.next() {
            try Task.checkCancellation()
            switch event {
            case .session(let session):
                try await process(session, context: context)
            case .finished(let summary):
                if summary.skippedNoDateCount > 0 {
                    progress.skipped[.noDate, default: 0] += summary.skippedNoDateCount
                    progress.processed += summary.skippedNoDateCount
                }
            }
        }
        await completeScan(stored: stored, context: context, canCommit: canCommit)
    }

    /// The library delta, and whether the change token may be committed after a successful scan.
    func prepareDelta() async throws -> (delta: LibraryDelta, canCommit: Bool) {
        guard let preparer = deps.preparer else {
            return (LibraryDelta(fullRescanReason: .noBaseline), false)
        }
        do {
            return (try await preparer.prepare(), true)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // An unusable history only costs a fingerprint-only comparison; don't commit, try again next scan.
            return (LibraryDelta(fullRescanReason: .historyUnreadable), false)
        }
    }

    /// What the sessions of this scan are compared against: the stored results of the current settings.
    func makeContext(stored: [StoredSessionResult], delta: LibraryDelta) -> SessionContext {
        let resultsKey = ScanResultsKey(
            sessionConfig: sessionConfig,
            clusteringConfig: deps.clusteringConfig,
            revision: revision
        ).value
        let previous = stored.filter { $0.resultsKey == resultsKey }
        return SessionContext(
            resultsKey: resultsKey,
            storedByID: Dictionary(stored.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last }),
            previousByContent: Dictionary(
                previous.map { ($0.fingerprint.content, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            planner: SessionChangePlanner(previous: previous.map(\.fingerprint), delta: delta)
        )
    }

    /// After the last session: removes the groups of sessions that are gone, writes the results, commits the token.
    func completeScan(stored: [StoredSessionResult], context: SessionContext, canCommit: Bool) async {
        let invalidIDs = Set(stored.filter { $0.resultsKey != context.resultsKey }.map(\.sessionID))
        let staleIDs = context.planner.staleSessionIDs.union(invalidIDs).subtracting(writtenSessionIDs)
        let removedClusterIDs = Set(staleIDs.flatMap { context.storedByID[$0]?.clusters.map(\.id) ?? [] })
            .subtracting(publishedClusterIDs)
        if !removedClusterIDs.isEmpty {
            clusterContinuation.yield(.removed(removedClusterIDs.sorted()))
        }
        pendingRemovals.formUnion(staleIDs)
        await flushResults()
        if canCommit, let tracker = deps.changeTracker {
            try? await tracker.commitScanCompleted()
        }
    }

    // MARK: - Progress

    /// Publishes a snapshot unless one was published less than `progressInterval` ago (`force` skips that check).
    func report(force: Bool = false) {
        let now = deps.now()
        guard throttle.shouldEmit(at: now, force: force) else { return }
        var snapshot = progress
        if !snapshot.phase.isFinal {
            snapshot.total = max(snapshot.total, snapshot.processed)
            snapshot.eta = snapshot.phase == .enumerating ? nil : ScanETAEstimator.eta(
                processed: snapshot.processed,
                total: snapshot.total,
                startedAt: analysisStartedAt,
                now: now
            )
        }
        progressContinuation.yield(snapshot)
    }
}
