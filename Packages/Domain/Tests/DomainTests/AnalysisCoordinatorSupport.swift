import Domain
import DomainTestSupport
import Foundation

/// Builders and fakes shared by the `AnalysisCoordinator` tests.
enum ScanFixture {
    static let base = Date(timeIntervalSince1970: 1_700_000_000)
    static let revision = 2
    static let threshold: Float = 0.5

    /// A photo of session `session` (one per day, larger is newer), `second` seconds into it.
    static func photo(_ id: String, session: Int, second: Int, favorite: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: base.addingTimeInterval(Double(session) * 86_400 + Double(second)),
            modificationDate: base,
            pixelWidth: 4_000,
            pixelHeight: 3_000,
            isFavorite: favorite,
            mediaSubtypes: []
        )
    }

    /// A Revision 2 print of `id`. Prints with the same `scene` are within the threshold; other scenes are not.
    static func print(_ id: String, scene: Int, jitter: Float = 0) -> FeaturePrint {
        var vector = [Float](repeating: 0, count: 4)
        vector[scene % 4] = 1
        vector[(scene + 1) % 4] = jitter
        return FeaturePrint(assetID: id, revision: revision, vector: vector, assetModificationDate: base)
    }

    static func measurement(sharpness: Float) -> QualityMeasurement {
        QualityMeasurement(
            version: 1,
            sharpness: sharpness,
            faceQuality: nil,
            aesthetics: nil,
            isUtility: nil,
            isEdited: false
        )
    }

    static let clusteringConfig = ClusteringConfig(thresholds: [revision: threshold])

    /// Collects both streams of a scan until they end.
    static func collect(_ streams: ScanStreams) async -> (updates: [ClusterUpdate], progress: [ScanProgress]) {
        async let updates: [ClusterUpdate] = {
            var result: [ClusterUpdate] = []
            for await update in streams.clusters {
                result.append(update)
            }
            return result
        }()
        async let progress: [ScanProgress] = {
            var result: [ScanProgress] = []
            for await snapshot in streams.progress {
                result.append(snapshot)
            }
            return result
        }()
        return await (updates, progress)
    }

    /// The IDs of every added group, in publishing order.
    static func addedIDs(_ updates: [ClusterUpdate]) -> [String] {
        updates.flatMap { update -> [String] in
            if case .added(let selections) = update { return selections.map(\.id) }
            return []
        }
    }

    /// Every added selection, in publishing order.
    static func added(_ updates: [ClusterUpdate]) -> [ClusterSelection] {
        updates.flatMap { update -> [ClusterSelection] in
            if case .added(let selections) = update { return selections }
            return []
        }
    }

    /// Every removed group ID, in publishing order.
    static func removedIDs(_ updates: [ClusterUpdate]) -> [String] {
        updates.flatMap { update -> [String] in
            if case .removed(let ids) = update { return ids }
            return []
        }
    }
}

/// `FeaturePrintService` with preset outcomes that records requests and concurrency, and can be slowed down or
/// blocked per photo. Unknown IDs are `.skipped(.iCloudOnly)`.
final class ScriptedFeaturePrintService: FeaturePrintService, @unchecked Sendable {
    // @unchecked: every mutable property is guarded by `lock`.
    let revision: Int
    private let outcomes: [String: FeaturePrintOutcome]
    private let delay: Duration
    private let lock = NSLock()
    private var requested: [String] = []
    private var running = 0
    private var maxRunning = 0
    private var blocked: Set<String>

    init(
        outcomes: [String: FeaturePrintOutcome],
        revision: Int = ScanFixture.revision,
        delay: Duration = .zero,
        blocked: Set<String> = []
    ) {
        self.outcomes = outcomes
        self.revision = revision
        self.delay = delay
        self.blocked = blocked
    }

    convenience init(prints: [FeaturePrint], delay: Duration = .zero, blocked: Set<String> = []) {
        self.init(
            outcomes: Dictionary(uniqueKeysWithValues: prints.map { ($0.assetID, .computed($0)) }),
            delay: delay,
            blocked: blocked
        )
    }

    /// Asset IDs requested so far, in order.
    var requestedIDs: [String] { lock.withLock { requested } }
    /// The highest number of concurrent calls seen.
    var maxConcurrency: Int { lock.withLock { maxRunning } }

    /// Lets blocked photos finish.
    func unblock(_ ids: Set<String>) {
        lock.withLock { blocked.subtract(ids) }
    }

    func featurePrint(for asset: PhotoAsset) async throws -> FeaturePrintOutcome {
        lock.withLock {
            requested.append(asset.id)
            running += 1
            maxRunning = max(maxRunning, running)
        }
        defer { lock.withLock { running -= 1 } }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        while lock.withLock({ blocked.contains(asset.id) }) {
            try await Task.sleep(for: .milliseconds(2))
        }
        try Task.checkCancellation()
        return outcomes[asset.id] ?? .skipped(.iCloudOnly)
    }
}

/// The real clustering engine, counting its calls.
final class CountingClusteringEngine: ClusteringEngine, @unchecked Sendable {
    // @unchecked: `count` is guarded by `lock`.
    private let engine = UnionFindClusteringEngine()
    private let lock = NSLock()
    private var count = 0

    var callCount: Int { lock.withLock { count } }

    func clusters(in session: [VectorItem], config: ClusteringConfig) throws(ClusteringError) -> [SimilarityCluster] {
        lock.withLock { count += 1 }
        return try engine.clusters(in: session, config: config)
    }
}

/// A coordinator wired to fakes, with handles on each of them.
struct ScanHarness {
    let library: MockPhotoLibraryRepository
    let tracker: MockLibraryChangeTracker
    let cache: MockFeaturePrintCache
    let service: ScriptedFeaturePrintService
    let clustering: CountingClusteringEngine
    let scorer: MockQualityScorer
    let thermal: MockThermalMonitor
    let results: MockClusterRepository
    let coordinator: AnalysisCoordinator

    init(
        assets: [PhotoAsset],
        service: ScriptedFeaturePrintService,
        cache: MockFeaturePrintCache = MockFeaturePrintCache(),
        results: MockClusterRepository = MockClusterRepository(),
        tracker: MockLibraryChangeTracker = MockLibraryChangeTracker(),
        scorer: MockQualityScorer = MockQualityScorer(),
        thermal: MockThermalMonitor = MockThermalMonitor(),
        clusteringConfig: ClusteringConfig = ScanFixture.clusteringConfig,
        settings: AnalysisCoordinator.Settings = AnalysisCoordinator.Settings(progressInterval: 0)
    ) {
        self.library = MockPhotoLibraryRepository(assets: assets)
        self.tracker = tracker
        self.cache = cache
        self.service = service
        self.clustering = CountingClusteringEngine()
        self.scorer = scorer
        self.thermal = thermal
        self.results = results
        self.coordinator = AnalysisCoordinator(
            library: library,
            preparer: IncrementalScanPreparer(tracker: tracker, cache: cache),
            changeTracker: tracker,
            cache: cache,
            featurePrints: service,
            segmenter: SessionSegmenter(),
            clustering: clustering,
            clusteringConfig: clusteringConfig,
            qualityScorer: scorer,
            smartSelection: SmartSelectionUseCase(),
            thermalMonitor: thermal,
            results: results,
            settings: settings
        )
    }

    /// Starts a scan of all photos (screenshots included) with `sessionConfig`.
    func start(sessionConfig: SessionConfig = .default) async -> ScanStreams {
        await coordinator.start(scope: ScanScope(excludeScreenshots: false), sessionConfig: sessionConfig)
    }

    /// Runs a whole scan of all photos and collects its streams.
    func scan(
        sessionConfig: SessionConfig = .default
    ) async -> (updates: [ClusterUpdate], progress: [ScanProgress]) {
        await ScanFixture.collect(await start(sessionConfig: sessionConfig))
    }
}

/// Polls `condition` every 2 ms for up to `timeout`; returns whether it became true.
func eventually(timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}
