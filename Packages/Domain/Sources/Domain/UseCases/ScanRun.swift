import Foundation

/// One scan of `AnalysisCoordinator`: owns the progress state, the throttling state and the two stream
/// continuations. Sessions are processed one after another (so groups are published in session order); the image
/// work inside a session runs in child tasks with a bounded width.
actor ScanRun {
    private let deps: AnalysisCoordinator.Dependencies
    private let scope: ScanScope
    private let sessionConfig: SessionConfig
    private let exclusions: ExclusionSet
    private let progressContinuation: AsyncStream<ScanProgress>.Continuation
    private let clusterContinuation: AsyncStream<ClusterUpdate>.Continuation
    private let revision: Int
    private let scoringVersion: Int

    // Progress.
    private var progress = ScanProgress()
    private var throttle: ScanProgressThrottle
    private var analysisStartedAt: Date

    // Throttling.
    private var pauseWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var nextWaiterID: UInt64 = 0

    // Results.
    private var publishedClusterIDs: Set<String> = []
    private var writtenSessionIDs: Set<String> = []
    private var pendingUpserts: [StoredSessionResult] = []
    private var pendingRemovals: Set<String> = []
    private var sessionsSinceFlush = 0

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
    private func scan() async throws {
        report(force: true)
        progress.total = await deps.library.assetCount(scope: scope)
        try Task.checkCancellation()

        var canCommit = deps.preparer != nil
        var delta = LibraryDelta(fullRescanReason: .noBaseline)
        if let preparer = deps.preparer {
            do {
                delta = try await preparer.prepare()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An unusable history only costs a fingerprint-only comparison; don't commit, try again next scan.
                delta = LibraryDelta(fullRescanReason: .historyUnreadable)
                canCommit = false
            }
        }

        let resultsKey = ScanResultsKey(
            sessionConfig: sessionConfig,
            clusteringConfig: deps.clusteringConfig,
            revision: revision
        ).value
        let stored = await deps.results.storedResults()
        try Task.checkCancellation()
        let previous = stored.filter { $0.resultsKey == resultsKey }
        let context = SessionContext(
            resultsKey: resultsKey,
            storedByID: Dictionary(stored.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last }),
            previousByContent: Dictionary(
                previous.map { ($0.fingerprint.content, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            planner: SessionChangePlanner(previous: previous.map(\.fingerprint), delta: delta)
        )

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

        let invalidIDs = Set(stored.filter { $0.resultsKey != resultsKey }.map(\.sessionID))
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

    // MARK: - Sessions

    /// What every session of one scan is compared against.
    private final class SessionContext: @unchecked Sendable {
        // @unchecked: only used from the `ScanRun` actor.
        let resultsKey: String
        let storedByID: [String: StoredSessionResult]
        let previousByContent: [SessionFingerprint.Content: StoredSessionResult]
        var planner: SessionChangePlanner

        init(
            resultsKey: String,
            storedByID: [String: StoredSessionResult],
            previousByContent: [SessionFingerprint.Content: StoredSessionResult],
            planner: SessionChangePlanner
        ) {
            self.resultsKey = resultsKey
            self.storedByID = storedByID
            self.previousByContent = previousByContent
            self.planner = planner
        }
    }

    /// Analyses, clusters, scores and publishes one session.
    private func process(_ session: PhotoSession, context: SessionContext) async throws {
        let photoCount = session.assets.count
        let assets = session.assets.filter { !exclusions.contains($0.id) }
        guard session.needsAnalysis, assets.count >= 2, let current = PhotoSession(assets: assets) else {
            progress.processed += photoCount
            report()
            return
        }

        let fingerprint = SessionFingerprint(current)
        var work = SessionWork(assets: assets)
        let clusters: [SimilarityCluster]
        let isReused: Bool
        if context.planner.classify(current) == .unchanged,
           let stored = context.previousByContent[fingerprint.content] {
            clusters = stored.clusters
            isReused = true
            let memberIDs = Set(clusters.flatMap(\.assetIDs))
            work.records = await deps.cache.validEntries(
                for: assets.filter { memberIDs.contains($0.id) },
                revision: revision
            )
        } else {
            isReused = false
            work.records = await deps.cache.validEntries(for: assets, revision: revision)
            progress.failed += work.records.values.filter { $0.status == .failed }.count
            try await computeMissingPrints(&work)
            clusters = try await cluster(&work)
        }
        progress.processed += photoCount - work.countedPhotos

        let selections = try await select(in: clusters, work: &work)
        publish(selections, sessionID: current.id, context: context)
        if !isReused {
            pendingUpserts.append(StoredSessionResult(
                fingerprint: fingerprint,
                clusters: selections.map { $0.cluster.withKeeper(nil) },
                resultsKey: context.resultsKey
            ))
            writtenSessionIDs.insert(current.id)
            sessionsSinceFlush += 1
            if sessionsSinceFlush >= deps.settings.resultsFlushInterval {
                await flushResults()
            }
        }
        if progress.phase == .clustering {
            progress.phase = .analyzing
            report(force: true)
        } else {
            report()
        }
    }

    /// The per-session state that the steps share.
    private struct SessionWork {
        let assets: [PhotoAsset]
        /// Valid records: cached ones plus the ones computed in this scan.
        var records: [String: AnalysisRecord] = [:]
        /// Asset IDs whose record must be written to the cache.
        var dirtyIDs: Set<String> = []
        /// Photos already added to `progress.processed`.
        var countedPhotos = 0

        init(assets: [PhotoAsset]) {
            self.assets = assets
        }
    }

    /// Computes the feature prints the cache doesn't have, `persistBatchSize` photos at a time.
    ///
    /// Every full batch except the last is saved at once, so a killed app loses at most one batch of a large
    /// session; the last batch is saved together with the quality measurements. Saves what was computed if the
    /// scan is cancelled.
    private func computeMissingPrints(_ work: inout SessionWork) async throws {
        let misses = work.assets.filter { work.records[$0.id] == nil }
        let batchSize = deps.settings.persistBatchSize
        var start = misses.startIndex
        while start < misses.endIndex {
            let end = min(start + batchSize, misses.endIndex)
            try await computePrints(of: Array(misses[start..<end]), into: &work)
            if end < misses.endIndex {
                await save(&work)
            }
            start = end
        }
    }

    /// Computes the prints of `batch` and adds their records to `work`.
    private func computePrints(of misses: [PhotoAsset], into work: inout SessionWork) async throws {
        let featurePrints = deps.featurePrints
        let (outcomes, wasCancelled) = await runBounded(misses, countsAsProgress: true) { asset in
            try await featurePrints.featurePrint(for: asset)
        }
        work.countedPhotos += outcomes.count
        let analyzedAt = deps.now()
        for asset in misses {
            guard let outcome = outcomes[asset.id] else { continue }
            switch outcome {
            case .skipped(let reason):
                progress.skipped[reason, default: 0] += 1
            case .computed, .failed:
                if case .failed = outcome {
                    progress.failed += 1
                }
                let record = AnalysisRecord(outcome: outcome, asset: asset, revision: revision, analyzedAt: analyzedAt)
                if let record {
                    work.records[asset.id] = record
                    work.dirtyIDs.insert(asset.id)
                }
            }
        }
        if wasCancelled {
            await save(&work)
            throw CancellationError()
        }
    }

    /// Clusters the photos that have a feature print.
    private func cluster(_ work: inout SessionWork) async throws -> [SimilarityCluster] {
        progress.phase = .clustering
        report(force: true)
        let items = work.assets.compactMap { asset -> VectorItem? in
            guard let featurePrint = work.records[asset.id]?.featurePrint else { return nil }
            return VectorItem(asset: asset, featurePrint: featurePrint)
        }
        do {
            return try deps.clustering.clusters(in: items, config: deps.clusteringConfig)
        } catch {
            await save(&work)
            switch error {
            case .missingThreshold(let revision):
                throw ScanFailure.missingThreshold(revision: revision)
            }
        }
    }

    /// Measures the members without a current measurement, saves every new record, and builds the suggestions.
    private func select(in clusters: [SimilarityCluster], work: inout SessionWork) async throws -> [ClusterSelection] {
        let visible = clusters.compactMap(withoutExcludedMembers)
        guard !visible.isEmpty else {
            await save(&work)
            return []
        }
        let memberIDs = Set(visible.flatMap(\.assetIDs))
        let members = work.assets.filter { memberIDs.contains($0.id) }
        var measurements: [String: QualityMeasurement] = [:]
        var toMeasure: [PhotoAsset] = []
        for member in members {
            if let measurement = work.records[member.id]?.quality(scoringVersion: scoringVersion) {
                measurements[member.id] = measurement
            } else {
                toMeasure.append(member)
            }
        }
        let scorer = deps.qualityScorer
        let (outcomes, wasCancelled) = await runBounded(toMeasure, countsAsProgress: false) { asset in
            try await scorer.measure(asset)
        }
        for (id, outcome) in outcomes {
            guard let measurement = outcome.measurement else { continue }
            measurements[id] = measurement
            if let record = work.records[id] {
                work.records[id] = record.withQuality(measurement)
                work.dirtyIDs.insert(id)
            }
        }
        await save(&work)
        if wasCancelled {
            throw CancellationError()
        }
        let assetsByID = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var signals: [String: QualitySignals] = [:]
        for (id, measurement) in measurements {
            if let asset = assetsByID[id] {
                signals[id] = QualitySignals(measurement: measurement, asset: asset)
            }
        }
        // Photos deleted while this session was measured are dropped once more before publishing.
        return deps.smartSelection.suggest(for: visible.compactMap(withoutExcludedMembers), signals: signals)
    }

    /// `cluster` without the photos deleted during the scan, or `nil` if fewer than two remain.
    private nonisolated func withoutExcludedMembers(_ cluster: SimilarityCluster) -> SimilarityCluster? {
        let remaining = cluster.assetIDs.filter { !exclusions.contains($0) }
        if remaining.count == cluster.assetIDs.count { return cluster }
        guard remaining.count >= 2 else { return nil }
        return SimilarityCluster(
            assetIDs: remaining,
            suggestedKeeperID: nil,
            averageDistance: cluster.averageDistance,
            isExactDuplicate: cluster.isExactDuplicate
        )
    }

    /// Writes the session's new and changed records in one `upsert`. A failed write only costs a re-analysis later.
    private func save(_ work: inout SessionWork) async {
        guard !work.dirtyIDs.isEmpty else { return }
        let records = work.assets.compactMap { work.dirtyIDs.contains($0.id) ? work.records[$0.id] : nil }
        work.dirtyIDs = []
        try? await deps.cache.upsert(records)
    }

    /// Publishes a session's groups: first the IDs of its previous groups that are gone, then the new ones.
    private func publish(_ selections: [ClusterSelection], sessionID: String, context: SessionContext) {
        let newIDs = Set(selections.map(\.id))
        if let previous = context.storedByID[sessionID] {
            let removed = previous.clusters.map(\.id).filter {
                !newIDs.contains($0) && !publishedClusterIDs.contains($0)
            }
            if !removed.isEmpty {
                clusterContinuation.yield(.removed(removed))
            }
        }
        guard !selections.isEmpty else { return }
        publishedClusterIDs.formUnion(newIDs)
        progress.clusterCount += selections.count
        clusterContinuation.yield(.added(selections))
    }

    /// Writes the pending session results. A failed write only means the clusters are recomputed next time.
    private func flushResults() async {
        guard !pendingUpserts.isEmpty || !pendingRemovals.isEmpty else { return }
        let upserts = pendingUpserts
        let removals = pendingRemovals
        pendingUpserts = []
        pendingRemovals = []
        sessionsSinceFlush = 0
        try? await deps.results.apply(upserted: upserts, removedSessionIDs: removals)
    }

    // MARK: - Bounded image work

    /// Runs `work` for every asset with at most the recommended width at a time, waiting while the scan is paused.
    ///
    /// Photos deleted during the scan are never started. Returns every result that arrived (also after a
    /// cancellation, so finished work can be saved) and whether the scan was cancelled.
    private func runBounded<Output: Sendable>(
        _ assets: [PhotoAsset],
        countsAsProgress: Bool,
        work: @escaping @Sendable (PhotoAsset) async throws -> Output
    ) async -> (results: [String: Output], wasCancelled: Bool) {
        guard !assets.isEmpty else { return ([:], Task.isCancelled) }
        var results: [String: Output] = [:]
        var wasCancelled = false
        let exclusions = exclusions
        await withTaskGroup(of: (String, Output?).self) { group in
            var running = 0
            var index = 0
            while index < assets.count {
                let width: Int
                do {
                    width = try await waitForWidth()
                } catch {
                    wasCancelled = true
                    break
                }
                if running >= width, let (id, output) = await group.next() {
                    running -= 1
                    record(id: id, output: output, into: &results, countsAsProgress: countsAsProgress)
                    continue
                }
                let asset = assets[index]
                index += 1
                guard !exclusions.contains(asset.id) else { continue }
                group.addTask {
                    // Checked again here: the photo may have been deleted while this task waited to start.
                    guard !exclusions.contains(asset.id) else { return (asset.id, nil) }
                    return (asset.id, try? await work(asset))
                }
                running += 1
            }
            if wasCancelled || Task.isCancelled {
                group.cancelAll()
            }
            for await (id, output) in group {
                record(id: id, output: output, into: &results, countsAsProgress: countsAsProgress)
            }
        }
        return (results, wasCancelled || Task.isCancelled)
    }

    /// Stores one finished result and advances the progress.
    private func record<Output>(
        id: String,
        output: Output?,
        into results: inout [String: Output],
        countsAsProgress: Bool
    ) {
        guard let output else { return }
        results[id] = output
        if countsAsProgress {
            progress.processed += 1
            report()
        }
    }

    // MARK: - Throttling

    /// The current width; waits (phase `.throttled`) while it is 0. Throws `CancellationError` if cancelled.
    private func waitForWidth() async throws -> Int {
        var width = progress.conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency)
        guard width == 0 else { return width }
        let resumedPhase = progress.phase
        progress.phase = .throttled
        report(force: true)
        while width == 0 {
            try Task.checkCancellation()
            let id = nextWaiterID
            nextWaiterID += 1
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        pauseWaiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancelPauseWaiter(id) }
            }
            width = progress.conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency)
        }
        progress.phase = resumedPhase
        report(force: true)
        return width
    }

    /// New conditions from the thermal monitor: published, and a paused scan goes on if they allow it.
    private func conditionsChanged(_ conditions: ScanConditions) {
        guard conditions != progress.conditions else { return }
        progress.conditions = conditions
        report(force: true)
        if conditions.recommendedConcurrency(fullConcurrency: deps.settings.fullConcurrency) > 0 {
            let waiters = pauseWaiters.values
            pauseWaiters = [:]
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    /// Ends one wait because its task was cancelled.
    private func cancelPauseWaiter(_ id: UInt64) {
        pauseWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Ends every wait.
    private func resumeAllPauseWaiters(throwing error: any Error) {
        let waiters = pauseWaiters.values
        pauseWaiters = [:]
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    // MARK: - Progress

    /// Publishes a snapshot unless one was published less than `progressInterval` ago (`force` skips that check).
    private func report(force: Bool = false) {
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
