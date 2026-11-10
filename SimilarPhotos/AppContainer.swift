import DataLayer
import Domain
import Presentation
import UIKit

/// Composition root: the only place where concrete Data implementations are created.
///
/// Services are built once and handed to view models as Domain protocols.
@MainActor
final class AppContainer: ViewModelFactory {
    let photoLibrary: any PhotoLibraryRepository
    let permissionService: any PhotoPermissionService
    let featurePrintService: any FeaturePrintService
    let featurePrintCache: any FeaturePrintCache
    let clusteringEngine: any ClusteringEngine
    /// Measures cluster members lazily (SPS-17); shares the image loader with the feature-print service.
    let qualityScorer: any QualityScorer
    let assetDeletionService: any AssetDeletionService
    let scopePreferencesStore: any ScopePreferencesStore
    /// Cuts the photo stream into shooting sessions; consumed by the scan coordinator (SPS-14).
    let sessionSegmenter: SessionSegmenter
    /// Library changes since the last completed scan (SPS-10); the coordinator commits after a successful scan.
    let libraryChangeTracker: any LibraryChangeTracker
    /// First step of every scan: the delta, the full-diff fallback and cache eviction (SPS-10).
    let incrementalScanPreparer: IncrementalScanPreparer
    /// Debounced (1 s) library changes while the app runs, for refreshing visible results (SPS-10).
    let libraryObserver: any LibraryChangeObserving
    /// Suggests keep / delete per cluster (SPS-18); the scan coordinator (SPS-14) runs it on ranked clusters.
    let smartSelection: SmartSelectionUseCase
    /// File-size estimates for the "will be deleted" summary (SPS-18).
    let assetSizeEstimator: any AssetSizeEstimator
    /// The user's keep / delete choice for the whole app session (SPS-18).
    let selectionStore: SelectionStore
    /// Thermal state and Low Power Mode, which throttle the scan (SPS-14).
    let thermalMonitor: any ThermalMonitor
    /// Clusters of analysed sessions with their fingerprints, reused by the next scan (SPS-14).
    let clusterRepository: any ClusterRepository
    /// Runs scans session by session and publishes groups while scanning (SPS-14).
    let scanCoordinator: any ScanCoordinating
    /// The scan of this app session, shared by every screen that shows it (SPS-14).
    let scanViewModel: ScanViewModel

    /// Similarity thresholds per Vision revision. Empty until the calibration spike on the labelled fixture set
    /// (SPS-16): with no threshold, a scan stops with "not calibrated" instead of guessing.
    static let clusteringConfig = ClusteringConfig(thresholds: [:])

    /// Builds every service once.
    init() {
        photoLibrary = PhotoKitLibraryRepository()
        permissionService = PhotoKitPermissionService()
        let imageLoader = PhotoKitImageLoader()
        featurePrintService = VisionFeaturePrintService(images: imageLoader)
        featurePrintCache = SwiftDataFeaturePrintCache()
        clusteringEngine = UnionFindClusteringEngine()
        qualityScorer = VisionQualityScorer(images: imageLoader, edits: PhotoKitAssetEditInspector())
        assetDeletionService = PhotoKitAssetDeletionService()
        scopePreferencesStore = UserDefaultsScopePreferencesStore(defaults: .standard)
        sessionSegmenter = SessionSegmenter(logger: OSLogSessionSegmentationLogger())
        let changeTracker = PhotoKitLibraryChangeTracker()
        libraryChangeTracker = changeTracker
        incrementalScanPreparer = IncrementalScanPreparer(tracker: changeTracker, cache: featurePrintCache)
        libraryObserver = PhotoKitLibraryObserver()
        smartSelection = SmartSelectionUseCase()
        let sizeEstimator = PhotoKitAssetSizeEstimator()
        assetSizeEstimator = sizeEstimator
        let selection = SelectionStore(sizes: sizeEstimator)
        selectionStore = selection
        let thermal = ProcessInfoThermalMonitor()
        thermalMonitor = thermal
        let results = FileClusterRepository()
        clusterRepository = results
        let coordinator = AnalysisCoordinator(
            library: photoLibrary,
            preparer: incrementalScanPreparer,
            changeTracker: changeTracker,
            cache: featurePrintCache,
            featurePrints: featurePrintService,
            segmenter: sessionSegmenter,
            clustering: clusteringEngine,
            clusteringConfig: Self.clusteringConfig,
            qualityScorer: qualityScorer,
            smartSelection: smartSelection,
            thermalMonitor: thermal,
            results: results
        )
        scanCoordinator = coordinator
        let lifecycle = UIKitAppLifecycle()
        scanViewModel = ScanViewModel(
            coordinator: coordinator,
            preferences: scopePreferencesStore,
            selection: selection,
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
    }

    /// A view model for the photo-library permission flow.
    func makePermissionViewModel() -> PermissionViewModel {
        PermissionViewModel(permissions: permissionService, openSettings: Self.openAppSettings)
    }

    /// A view model for the album and scope sheet; `onApply` receives the saved choice.
    func makeScopeSelectionViewModel(
        onApply: @escaping @MainActor (ScopePreferences) -> Void
    ) -> ScopeSelectionViewModel {
        ScopeSelectionViewModel(
            library: photoLibrary,
            permissions: permissionService,
            store: scopePreferencesStore,
            onApply: onApply
        )
    }

    /// Opens the app's own page in the Settings app.
    private static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
