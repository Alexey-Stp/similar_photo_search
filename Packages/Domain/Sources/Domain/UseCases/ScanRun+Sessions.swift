import Foundation

/// The per-session steps of a scan: cached prints, missing prints, clustering, quality, suggestions, publishing.
extension ScanRun {
    // MARK: - Sessions

    /// What every session of one scan is compared against.
    final class SessionContext: @unchecked Sendable {
        // @unchecked: only used from the `ScanRun` actor.
        let resultsKey: String
        let storedByID: [String: StoredSessionResult]
        let previousByContent: [SessionFingerprint.Content: StoredSessionResult]
        var planner: SessionChangePlanner

        /// Creates the context of one scan.
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
    func process(_ session: PhotoSession, context: SessionContext) async throws {
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
    struct SessionWork {
        let assets: [PhotoAsset]
        /// Valid records: cached ones plus the ones computed in this scan.
        var records: [String: AnalysisRecord] = [:]
        /// Asset IDs whose record must be written to the cache.
        var dirtyIDs: Set<String> = []
        /// Photos already added to `progress.processed`.
        var countedPhotos = 0

        /// Starts the work on the session's remaining photos.
        init(assets: [PhotoAsset]) {
            self.assets = assets
        }
    }

    /// Computes the feature prints the cache doesn't have, `persistBatchSize` photos at a time.
    ///
    /// Every full batch except the last is saved at once, so a killed app loses at most one batch of a large
    /// session; the last batch is saved together with the quality measurements. Saves what was computed if the
    /// scan is cancelled.
    func computeMissingPrints(_ work: inout SessionWork) async throws {
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
    func computePrints(of misses: [PhotoAsset], into work: inout SessionWork) async throws {
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
    func cluster(_ work: inout SessionWork) async throws -> [SimilarityCluster] {
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
    func select(in clusters: [SimilarityCluster], work: inout SessionWork) async throws -> [ClusterSelection] {
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
    nonisolated func withoutExcludedMembers(_ cluster: SimilarityCluster) -> SimilarityCluster? {
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
    func save(_ work: inout SessionWork) async {
        guard !work.dirtyIDs.isEmpty else { return }
        let records = work.assets.compactMap { work.dirtyIDs.contains($0.id) ? work.records[$0.id] : nil }
        work.dirtyIDs = []
        try? await deps.cache.upsert(records)
    }

    /// Publishes a session's groups: first the IDs of its previous groups that are gone, then the new ones.
    func publish(_ selections: [ClusterSelection], sessionID: String, context: SessionContext) {
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
    func flushResults() async {
        guard !pendingUpserts.isEmpty || !pendingRemovals.isEmpty else { return }
        let upserts = pendingUpserts
        let removals = pendingRemovals
        pendingUpserts = []
        pendingRemovals = []
        sessionsSinceFlush = 0
        try? await deps.results.apply(upserted: upserts, removedSessionIDs: removals)
    }
}
