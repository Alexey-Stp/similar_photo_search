#if os(iOS)
@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing
import Vision

private let isDeviceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Device-only: Vision on the Neural Engine gives different numbers from the Simulator. Run on an iPhone with an
/// authorized library of at least 20 photos stored on the device, with the scheme environment variable
/// `RUN_DEVICE_PERFORMANCE_TESTS=1`.
struct VisionFeaturePrintDeviceTests {
    /// On a device, vDSP distances between real photos match Vision's within 1e-4.
    @Test(.enabled(if: isDeviceRun, "Device-only Vision test"))
    func realPhotosMatchVisionDistancesWithin1e4() async throws {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let loader = PhotoKitImageLoader()
        let extractor = VisionFeaturePrintExtractor()
        #expect(extractor.revision == VNGenerateImageFeaturePrintRequestRevision2)

        var observations: [VNFeaturePrintObservation] = []
        let pages = PhotoKitLibraryRepository().assetPages(scope: ScanScope(excludeScreenshots: false), pageSize: 50)
        for try await page in pages {
            for asset in page where observations.count < 20 {
                guard let image = try? await loader.loadImage(
                    assetID: asset.id,
                    targetSize: ImageLoadingDefaults.targetSize
                ) else { continue }
                observations.append(try extractor.makeObservation(for: image))
            }
            if observations.count >= 20 {
                break
            }
        }
        try #require(observations.count >= 20, "Keep at least 20 photos on the device")

        for (first, second) in zip(observations, observations.dropFirst()) {
            let visionDistance = try VisionFeaturePrintExtractorTests.visionDistance(first, second)
            let vectorDistance = VectorMath.euclideanDistance(
                try VisionFeaturePrintExtractorTests.vector(first),
                try VisionFeaturePrintExtractorTests.vector(second)
            )
            #expect(abs(visionDistance - vectorDistance) <= 1e-4)
        }
        let selfDistance = try VisionFeaturePrintExtractorTests.visionDistance(observations[0], observations[0])
        #expect(selfDistance <= 1e-4)
    }
}
#endif
