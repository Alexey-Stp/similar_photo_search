import DataLayer
import Domain
import Foundation
import Testing

private let isDevicePerformanceRun = ProcessInfo.processInfo.environment["RUN_DEVICE_PERFORMANCE_TESTS"] == "1"

/// Device-only: run on an iPhone 13 with the scheme environment variable `RUN_DEVICE_PERFORMANCE_TESTS=1`.
/// Needs no photo library: it writes 50,000 synthetic Revision 2 records (about 150 MB) to a temporary store.
struct AnalysisCachePerformanceTests {
    /// 50,000 Revision 2 vectors are read back, all valid, in under 1.5 s from a cold context.
    @Test(.enabled(if: isDevicePerformanceRun, "Device-only performance test"))
    func readsFiftyThousandVectorsUnderOneAndAHalfSeconds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AnalysisCachePerformance-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let count = 50_000
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let assets = (0..<count).map { index in
            PhotoAsset(
                id: "asset-\(index)",
                creationDate: date,
                modificationDate: date,
                pixelWidth: 4_032,
                pixelHeight: 3_024,
                isFavorite: false,
                mediaSubtypes: []
            )
        }
        let writer = SwiftDataFeaturePrintCache(location: .directory(directory))
        for start in stride(from: 0, to: count, by: 5_000) {
            let records = assets[start..<min(start + 5_000, count)].map { asset in
                AnalysisRecord(
                    featurePrint: FeaturePrint(
                        assetID: asset.id,
                        revision: 2,
                        vector: [Float](repeating: 0.5, count: 768),
                        assetModificationDate: date
                    ),
                    analyzedAt: date
                )
            }
            try await writer.upsert(records)
        }

        // A second instance has a cold context, like the next launch.
        let reader = SwiftDataFeaturePrintCache(location: .directory(directory))
        var hits = 0
        let elapsed = await ContinuousClock().measure {
            hits = await reader.validEntries(for: assets, revision: 2).count
        }
        #expect(hits == count)
        #expect(elapsed < .milliseconds(1_500))
    }
}
