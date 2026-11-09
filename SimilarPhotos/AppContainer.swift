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
    let qualityScorer: any QualityScorer
    let assetDeletionService: any AssetDeletionService
    let scopePreferencesStore: any ScopePreferencesStore
    /// Cuts the photo stream into shooting sessions; consumed by the scan coordinator (SPS-14).
    let sessionSegmenter: SessionSegmenter

    init() {
        photoLibrary = PhotoKitLibraryRepository()
        permissionService = PhotoKitPermissionService()
        let imageLoader = PhotoKitImageLoader()
        featurePrintService = VisionFeaturePrintService(images: imageLoader)
        featurePrintCache = SwiftDataFeaturePrintCache()
        clusteringEngine = UnionFindClusteringEngine()
        qualityScorer = VisionQualityScorer()
        assetDeletionService = PhotoKitAssetDeletionService()
        scopePreferencesStore = UserDefaultsScopePreferencesStore(defaults: .standard)
        sessionSegmenter = SessionSegmenter(logger: OSLogSessionSegmentationLogger())
    }

    func makePermissionViewModel() -> PermissionViewModel {
        PermissionViewModel(permissions: permissionService, openSettings: Self.openAppSettings)
    }

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
