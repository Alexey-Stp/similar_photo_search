#if os(iOS) && !targetEnvironment(simulator)
@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing

private let isDeviceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Real Vision on a physical device only: in the Simulator the Vision models behave differently (SPS-12), and the
/// macOS CI virtual machine hung on real-Vision tests.
struct QualityScoringDeviceTests {
    /// Vision finds no face in a code-drawn pattern: face quality is `nil`, not 0.
    @Test func aPictureWithoutFacesHasNoFaceQuality() throws {
        let image = LoadedImage(cgImage: try SyntheticImages.pattern(0), orientation: .up)
        let result = try VisionQualityExtractor().analyze(image)
        #expect(result.faceQuality == nil)
        if #available(iOS 18, *) {
            #expect(result.aesthetics != nil)
            #expect(result.isUtility != nil)
        } else {
            #expect(result.aesthetics == nil)
        }
    }

    /// Per-image scoring (sharpness, Vision, edit check) takes under 60 ms on average at 512 px, on an iPhone 13.
    /// Needs an authorized library with at least 20 photos stored on the device and `RUN_DEVICE_PERFORMANCE_TESTS=1`.
    @Test(.enabled(if: isDeviceRun, "Device-only performance test"))
    func scoringOneImageTakesUnder60Milliseconds() async throws {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let loader = PhotoKitImageLoader()
        let scorer = VisionQualityScorer(images: loader, edits: PhotoKitAssetEditInspector())

        // Each image is measured right after it is loaded and then dropped, so at most one is held at a time.
        // The first measurement loads the Vision models and is not part of the budget.
        let clock = ContinuousClock()
        var measured = 0
        var total = Duration.zero
        let pages = PhotoKitLibraryRepository().assetPages(scope: ScanScope(excludeScreenshots: false), pageSize: 50)
        for try await page in pages {
            for asset in page where measured < 21 {
                guard let image = try? await loader.loadImage(
                    assetID: asset.id,
                    targetSize: ImageLoadingDefaults.targetSize
                ) else { continue }
                let elapsed = try clock.measure {
                    _ = try scorer.measurement(of: image, assetID: asset.id)
                }
                if measured > 0 {
                    total += elapsed
                }
                measured += 1
            }
            if measured >= 21 {
                break
            }
        }
        try #require(measured >= 21, "Keep at least 21 photos on the device")

        let mean = total / (measured - 1)
        #expect(mean < .milliseconds(60), "Mean per-image scoring took \(mean)")
    }
}
#endif
