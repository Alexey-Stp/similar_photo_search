import DataLayer
import Domain
import Testing

/// Smoke tests: every Data implementation exists and conforms to its Domain protocol.
/// Methods are not called: placeholders `fatalError`, and real PhotoKit calls need a device and an authorized library.
struct PlaceholderConformanceTests {
    @Test func everyImplementationConformsToItsDomainProtocol() {
        let photoLibrary: any PhotoLibraryRepository = PhotoKitLibraryRepository()
        let permissions: any PhotoPermissionService = PhotoKitPermissionService()
        let featurePrints: any FeaturePrintService = VisionFeaturePrintService()
        let cache: any FeaturePrintCache = SwiftDataFeaturePrintCache()
        let clustering: any ClusteringEngine = UnionFindClusteringEngine()
        let scorer: any QualityScorer = VisionQualityScorer()
        let deletion: any AssetDeletionService = PhotoKitAssetDeletionService()
        let images: any ImageLoading = PhotoKitImageLoader()
        let sessionLog: any SessionSegmentationLogging = OSLogSessionSegmentationLogger()

        let services: [any Sendable] = [
            photoLibrary, permissions, featurePrints, cache, clustering, scorer, deletion, images, sessionLog
        ]
        #expect(services.count == 9)
    }
}
