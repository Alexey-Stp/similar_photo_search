import DataLayer
import Domain
import Testing

/// Smoke tests: every Data implementation exists and conforms to its Domain protocol.
/// The placeholder methods are never called because they `fatalError`.
struct PlaceholderConformanceTests {
    @Test func everyImplementationConformsToItsDomainProtocol() {
        let photoLibrary: any PhotoLibraryRepository = PhotoKitLibraryRepository()
        let featurePrints: any FeaturePrintService = VisionFeaturePrintService()
        let cache: any FeaturePrintCache = SwiftDataFeaturePrintCache()
        let clustering: any ClusteringEngine = UnionFindClusteringEngine()
        let scorer: any QualityScorer = VisionQualityScorer()
        let deletion: any AssetDeletionService = PhotoKitAssetDeletionService()

        let services: [any Sendable] = [photoLibrary, featurePrints, cache, clustering, scorer, deletion]
        #expect(services.count == 6)
    }
}
