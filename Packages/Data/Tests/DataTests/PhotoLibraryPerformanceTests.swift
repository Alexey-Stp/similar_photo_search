import DataLayer
import Domain
import Foundation
import Photos
import Testing

private let isDevicePerformanceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Device-only: needs a real, authorized library. Run on an iPhone 12 seeded with at least 50,000 photos,
/// with the scheme environment variable `RUN_DEVICE_PERFORMANCE_TESTS=1`.
struct PhotoLibraryPerformanceTests {
    @Test(.enabled(if: isDevicePerformanceRun, "Device-only performance test"))
    func enumeratesFiftyThousandAssetsUnderTwoSeconds() async throws {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let repository = PhotoKitLibraryRepository()
        let scope = ScanScope(excludeScreenshots: false)
        let total = await repository.assetCount(scope: scope)
        try #require(total >= 50_000, "Seed the device library with at least 50,000 photos")

        var delivered = 0
        let elapsed = try await ContinuousClock().measure {
            for try await page in repository.assetPages(scope: scope, pageSize: 500) {
                delivered += page.count
            }
        }
        #expect(delivered == total)
        #expect(elapsed < .seconds(2))
    }
}
