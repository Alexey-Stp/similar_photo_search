#if os(iOS)
import DataLayer
import Domain
import Foundation
import os
import Photos
import Testing

private let isDevicePerformanceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Device-only: needs a real, authorized library. Run on an iPhone 12 with at least 10,000 photos whose originals are
/// on the device (Settings › Photos › Download and Keep Originals), and the scheme environment variable
/// `RUN_DEVICE_PERFORMANCE_TESTS=1`. The absolute 250 MB peak is checked in Instruments
/// (Allocations); this test checks that the pipeline itself keeps memory flat over a 10k batch.
struct ImageLoadingPerformanceTests {
    @Test(.enabled(if: isDevicePerformanceRun, "Device-only memory test"))
    func tenThousandImagesKeepMemoryFlat() async throws {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        var assetIDs: [String] = []
        let pages = PhotoKitLibraryRepository().assetPages(scope: ScanScope(excludeScreenshots: false), pageSize: 500)
        for try await page in pages {
            assetIDs += page.map(\.id)
            if assetIDs.count >= 10_000 {
                break
            }
        }
        try #require(assetIDs.count >= 10_000, "Seed the device library with at least 10,000 photos")

        let baseline = os_proc_available_memory()
        var lowest = baseline
        var loaded = 0
        for await outcome in PhotoKitImageLoader().loadBatch(Array(assetIDs.prefix(10_000))) {
            if case .success = outcome.result {
                loaded += 1
            }
            lowest = min(lowest, os_proc_available_memory())
        }

        let growthInMegabytes = (baseline - lowest) / (1_024 * 1_024)
        // Every photo must really be decoded, or skipped photos would make the memory result look better than it is.
        #expect(loaded == 10_000, "Only \(loaded) of 10,000 photos loaded; keep originals on the device")
        // A bounded window holds at most a few 512 px images (about 1 MB each); growth stays far below the budget.
        #expect(growthInMegabytes < 100, "Memory grew by \(growthInMegabytes) MB")
    }
}
#endif
