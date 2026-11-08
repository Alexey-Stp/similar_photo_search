import DataLayer
import Domain
import Presentation

/// Composition root: the only place where concrete Data implementations are created.
///
/// Services are built once and handed to view models as Domain protocols.
@MainActor
final class AppContainer: ViewModelFactory {
    let photoLibrary: any PhotoLibraryRepository
    let featurePrintService: any FeaturePrintService
    let featurePrintCache: any FeaturePrintCache
    let clusteringEngine: any ClusteringEngine
    let qualityScorer: any QualityScorer
    let assetDeletionService: any AssetDeletionService

    init() {
        photoLibrary = PhotoKitLibraryRepository()
        featurePrintService = VisionFeaturePrintService()
        featurePrintCache = SwiftDataFeaturePrintCache()
        clusteringEngine = UnionFindClusteringEngine()
        qualityScorer = VisionQualityScorer()
        assetDeletionService = PhotoKitAssetDeletionService()
    }

    func makeRootViewModel() -> RootViewModel {
        RootViewModel(photoLibrary: photoLibrary)
    }
}
