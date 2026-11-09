import DataLayer
import Domain
import Testing

/// Smoke tests: every Data implementation exists and conforms to its Domain protocol.
/// Methods are not called: placeholders `fatalError`, and real PhotoKit calls need a device and an authorized library.
struct PlaceholderConformanceTests {
    /// Every Data implementation can be built and used as its Domain protocol.
    @Test func everyImplementationConformsToItsDomainProtocol() {
        let photoLibrary: any PhotoLibraryRepository = PhotoKitLibraryRepository()
        let permissions: any PhotoPermissionService = PhotoKitPermissionService()
        let images: any ImageLoading = PhotoKitImageLoader()
        let featurePrints: any FeaturePrintService = VisionFeaturePrintService(images: images)
        let cache: any FeaturePrintCache = SwiftDataFeaturePrintCache()
        let clustering: any ClusteringEngine = UnionFindClusteringEngine()
        let scorer: any QualityScorer = VisionQualityScorer()
        let deletion: any AssetDeletionService = PhotoKitAssetDeletionService()
        let sessionLog: any SessionSegmentationLogging = OSLogSessionSegmentationLogger()
        let changeTracker: any LibraryChangeTracker = PhotoKitLibraryChangeTracker()
        let libraryObserver: any LibraryChangeObserving = PhotoKitLibraryObserver()

        let services: [any Sendable] = [
            photoLibrary, permissions, featurePrints, cache, clustering, scorer, deletion, images, sessionLog,
            changeTracker, libraryObserver
        ]
        #expect(services.count == 11)
    }
}
