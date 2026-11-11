import CoreGraphics
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
    /// The home dashboard of this app session (SPS-20).
    let homeViewModel: HomeViewModel
    /// Thumbnails for the group list over `PHCachingImageManager` (SPS-21).
    let thumbnailLoader: any ThumbnailLoading
    /// The group list of this app session (SPS-21).
    let clusterListViewModel: ClusterListViewModel
    /// Screen-size images for the comparison, local only, never the original size (SPS-22).
    let screenImageLoader: any ScreenImageLoading = PhotoKitScreenImageBridge(loader: PhotoKitScreenImageLoader())
    /// Which photos have edits, for the comparison's "Edited" badge (SPS-22).
    let editStatusProvider: any PhotoEditStatusProviding = PhotoKitEditStatusProvider(
        inspector: PhotoKitAssetEditInspector()
    )

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
        assetDeletionService = PhotoKitAssetDeletionService(chunksAfterFailure: false)
        scopePreferencesStore = UserDefaultsScopePreferencesStore(defaults: .standard)
        sessionSegmenter = SessionSegmenter(logger: OSLogSessionSegmentationLogger())
        libraryChangeTracker = PhotoKitLibraryChangeTracker()
        incrementalScanPreparer = IncrementalScanPreparer(tracker: libraryChangeTracker, cache: featurePrintCache)
        libraryObserver = PhotoKitLibraryObserver()
        smartSelection = SmartSelectionUseCase()
        assetSizeEstimator = PhotoKitAssetSizeEstimator()
        selectionStore = SelectionStore(sizes: assetSizeEstimator)
        thermalMonitor = ProcessInfoThermalMonitor()
        clusterRepository = FileClusterRepository()
        scanCoordinator = AnalysisCoordinator(
            library: photoLibrary,
            preparer: incrementalScanPreparer,
            changeTracker: libraryChangeTracker,
            cache: featurePrintCache,
            featurePrints: featurePrintService,
            segmenter: sessionSegmenter,
            clustering: clusteringEngine,
            clusteringConfig: Self.clusteringConfig,
            qualityScorer: qualityScorer,
            smartSelection: smartSelection,
            thermalMonitor: thermalMonitor,
            results: clusterRepository
        )
        let lifecycle = UIKitAppLifecycle()
        scanViewModel = ScanViewModel(
            coordinator: scanCoordinator,
            preferences: scopePreferencesStore,
            selection: selectionStore,
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
        homeViewModel = HomeViewModel(scan: scanViewModel, results: clusterRepository, libraryChanges: libraryObserver)
        thumbnailLoader = PhotoKitThumbnailBridge(loader: PhotoKitThumbnailLoader())
        clusterListViewModel = ClusterListViewModel(
            scan: scanViewModel,
            library: photoLibrary,
            sizes: assetSizeEstimator,
            thumbnails: thumbnailLoader,
            libraryChanges: libraryObserver
        )
    }

    /// A view model for the photo-library permission flow.
    func makePermissionViewModel() -> PermissionViewModel {
        PermissionViewModel(
            permissions: permissionService,
            library: photoLibrary,
            openSettings: Self.openAppSettings
        )
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

    /// The full-screen comparison of one group over the session's group list.
    func makePhotoComparisonViewModel(clusterID: String) -> PhotoComparisonViewModel {
        PhotoComparisonViewModel(
            clusterID: clusterID,
            list: clusterListViewModel,
            screenImages: screenImageLoader,
            edits: editStatusProvider
        )
    }

    /// Opens the app's own page in the Settings app.
    private static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Adapts the Data thumbnail loader (`LoadedImage`, EXIF orientation) to Presentation's `ThumbnailLoading`.
///
/// Lives here because only the composition root sees both packages. Ending the returned stream ends the inner one,
/// which cancels the PhotoKit request.
private struct PhotoKitThumbnailBridge: ThumbnailLoading {
    let loader: PhotoKitThumbnailLoader

    /// The Data stream mapped to `Thumbnail`; ending it cancels the request.
    func thumbnail(for assetID: String, pixelSize: CGSize) -> AsyncStream<Thumbnail> {
        let images = loader.thumbnail(for: assetID, size: pixelSize)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await image in images {
                    continuation.yield(Thumbnail(cgImage: image.cgImage, exifOrientation: image.orientation))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Forwards to the Data loader.
    func prefetch(_ assetIDs: [String], pixelSize: CGSize) async {
        await loader.prefetch(assetIDs, size: pixelSize)
    }

    /// Forwards to the Data loader.
    func stopPrefetching(_ assetIDs: [String], pixelSize: CGSize) async {
        await loader.stopPrefetching(assetIDs, size: pixelSize)
    }

    /// Forwards to the Data loader.
    func stopAllPrefetching() async {
        await loader.stopAllPrefetching()
    }
}

/// Adapts the Data screen-image loader (`ScreenImageOutcome`, EXIF orientation) to Presentation's
/// `ScreenImageLoading`. Cancelling the calling task cancels the PhotoKit request.
private struct PhotoKitScreenImageBridge: ScreenImageLoading {
    let loader: PhotoKitScreenImageLoader

    /// The Data outcome mapped to `ScreenImage`; a local preview is flagged "Original in iCloud".
    func screenImage(for assetID: String, pixelSize: CGSize) async -> ScreenImage? {
        switch await loader.screenImage(for: assetID, size: pixelSize) {
        case .original(let image):
            ScreenImage(image: Self.thumbnail(image), isOriginalInCloud: false)
        case .localPreview(let image):
            ScreenImage(image: Self.thumbnail(image), isOriginalInCloud: true)
        case .unavailable:
            nil
        }
    }

    /// The Data image as a Presentation `Thumbnail`.
    private static func thumbnail(_ image: LoadedImage) -> Thumbnail {
        Thumbnail(cgImage: image.cgImage, exifOrientation: image.orientation)
    }
}
