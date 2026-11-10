import Foundation

/// Runs library scans session by session, newest first, and publishes each session's groups as soon as it is done.
///
/// Per scan:
/// 1. `IncrementalScanPreparer.prepare()` (the library delta; purges deleted photos from the cache).
/// 2. Every photo of the scope is enumerated (metadata only) and cut into sessions by `SessionSegmenter`.
///    Single-photo sessions are skipped before any image is loaded.
/// 3. Each session is classified by `SessionChangePlanner` against the stored results (`ClusterRepository`):
///    - unchanged: its stored clusters are reused, nothing is analysed;
///    - changed: cached feature prints are reused, the missing ones are computed (bounded width), and the session
///      is clustered again.
/// 4. Cluster members get a quality measurement (cached or measured), every cluster gets its Smart Selection
///    suggestion, the new prints and measurements are saved in one cache `upsert`, and the session's groups are
///    published on the cluster stream.
/// 5. After the last session, the clusters of sessions that no longer exist are published as removed and deleted
///    from the repository, and the library change token is committed.
///
/// Throttling: the width of the image work follows `ThermalMonitor` (`ScanConditions.recommendedConcurrency`);
/// at `.critical` the scan pauses (phase `.throttled`) until the device cools down.
/// Cancelling stops the work within the cancellation latency of the image services; prints and measurements
/// computed so far are saved, so a later scan analyses only the rest.
public actor AnalysisCoordinator: ScanCoordinating {
    /// Tuning of the scan.
    public struct Settings: Sendable {
        /// The width of the image work on a cool device on mains power.
        public var fullConcurrency: Int
        /// The page size used to enumerate the library.
        public var pageSize: Int
        /// The shortest time between two progress snapshots.
        public var progressInterval: TimeInterval
        /// Stored session results are written after this many analysed sessions (and at the end of a scan).
        public var resultsFlushInterval: Int
        /// New feature prints of a large session are saved every this many photos, so a killed app loses little.
        public var persistBatchSize: Int

        /// Creates settings. The defaults: 4 photos at a time, pages of 500, 10 progress updates per second,
        /// results written every 20 sessions, prints saved every 200 photos.
        public init(
            fullConcurrency: Int = 4,
            pageSize: Int = 500,
            progressInterval: TimeInterval = 0.1,
            resultsFlushInterval: Int = 20,
            persistBatchSize: Int = 200
        ) {
            self.fullConcurrency = max(1, fullConcurrency)
            self.pageSize = max(1, pageSize)
            self.progressInterval = max(0, progressInterval)
            self.resultsFlushInterval = max(1, resultsFlushInterval)
            self.persistBatchSize = max(1, persistBatchSize)
        }
    }

    /// Everything a scan needs. Shared by every run.
    struct Dependencies: Sendable {
        let library: any PhotoLibraryRepository
        let preparer: IncrementalScanPreparer?
        let changeTracker: (any LibraryChangeTracker)?
        let cache: any FeaturePrintCache
        let featurePrints: any FeaturePrintService
        let segmenter: SessionSegmenter
        let clustering: any ClusteringEngine
        let clusteringConfig: ClusteringConfig
        let qualityScorer: any QualityScorer
        let smartSelection: SmartSelectionUseCase
        let thermalMonitor: any ThermalMonitor
        let results: any ClusterRepository
        let settings: Settings
        let now: @Sendable () -> Date
    }

    private let dependencies: Dependencies
    private let exclusions = ExclusionSet()
    private var currentRun: Task<Void, Never>?

    /// Creates the coordinator.
    /// - Parameters:
    ///   - library: Enumerates the photos of the scope.
    ///   - preparer: The first step of a scan (library delta, cache eviction). Without it every scan compares
    ///     sessions by fingerprint only, like a full rescan.
    ///   - changeTracker: Committed after a successful scan. Pass the tracker `preparer` uses.
    ///   - cache: Feature prints and quality measurements.
    ///   - featurePrints: Computes the missing feature prints.
    ///   - segmenter: Cuts the photo stream into sessions.
    ///   - clustering: Clusters one session.
    ///   - clusteringConfig: Thresholds and the other clustering parameters.
    ///   - qualityScorer: Measures cluster members.
    ///   - smartSelection: Suggests the keeper and the photos to delete per cluster.
    ///   - thermalMonitor: Thermal state and Low Power Mode.
    ///   - results: Stored clusters with their session fingerprints.
    ///   - settings: Tuning.
    ///   - now: The clock for progress throttling, ETA and `AnalysisRecord.analyzedAt`.
    public init(
        library: any PhotoLibraryRepository,
        preparer: IncrementalScanPreparer?,
        changeTracker: (any LibraryChangeTracker)?,
        cache: any FeaturePrintCache,
        featurePrints: any FeaturePrintService,
        segmenter: SessionSegmenter,
        clustering: any ClusteringEngine,
        clusteringConfig: ClusteringConfig,
        qualityScorer: any QualityScorer,
        smartSelection: SmartSelectionUseCase,
        thermalMonitor: any ThermalMonitor,
        results: any ClusterRepository,
        settings: Settings = Settings(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        dependencies = Dependencies(
            library: library,
            preparer: preparer,
            changeTracker: changeTracker,
            cache: cache,
            featurePrints: featurePrints,
            segmenter: segmenter,
            clustering: clustering,
            clusteringConfig: clusteringConfig,
            qualityScorer: qualityScorer,
            smartSelection: smartSelection,
            thermalMonitor: thermalMonitor,
            results: results,
            settings: settings,
            now: now
        )
    }

    /// Starts a scan; a running scan is cancelled first, and the new one starts after it has stopped.
    public func start(scope: ScanScope, sessionConfig: SessionConfig) -> ScanStreams {
        let previous = currentRun
        previous?.cancel()
        let (progress, progressContinuation) = AsyncStream.makeStream(
            of: ScanProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let (clusters, clusterContinuation) = AsyncStream.makeStream(
            of: ClusterUpdate.self,
            bufferingPolicy: .unbounded
        )
        let run = ScanRun(
            dependencies: dependencies,
            scope: scope,
            sessionConfig: sessionConfig,
            exclusions: exclusions,
            progress: progressContinuation,
            clusters: clusterContinuation
        )
        currentRun = Task {
            await previous?.value
            await run.execute()
        }
        return ScanStreams(progress: progress, clusters: clusters)
    }

    /// Cancels the running scan.
    public func cancel() {
        currentRun?.cancel()
    }

    /// Excludes deleted photos from the running scan (and any later one in this app session).
    public func excludeDeleted(_ assetIDs: Set<String>) {
        exclusions.insert(assetIDs)
    }

    /// Waits until the current scan (if any) has ended. For tests and orderly shutdown.
    public func waitUntilIdle() async {
        await currentRun?.value
    }
}

/// Asset IDs deleted by the user while the app runs; read by the image work without hopping to an actor.
final class ExclusionSet: @unchecked Sendable {
    // @unchecked: `ids` is only touched under `lock`.
    private let lock = NSLock()
    private var ids: Set<String> = []

    /// Adds IDs.
    func insert(_ newIDs: Set<String>) {
        lock.lock()
        ids.formUnion(newIDs)
        lock.unlock()
    }

    /// Whether `id` was deleted.
    func contains(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }
}
