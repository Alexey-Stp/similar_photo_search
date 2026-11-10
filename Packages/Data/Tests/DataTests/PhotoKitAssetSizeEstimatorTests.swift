@testable import DataLayer
import Foundation
import Testing

/// Summing the undocumented `fileSize` values (SPS-18). The PhotoKit fetch itself needs a real library.
struct PhotoKitAssetSizeEstimatorTests {
    @Test func knownSizesAreAdded() {
        let values: [Any?] = [NSNumber(value: 1_000), Int64(2_000), 500]
        #expect(PhotoKitAssetSizeEstimator.totalSize(of: values) == 3_500)
    }

    @Test func missingAndInvalidValuesAreSkipped() {
        let values: [Any?] = [nil, "big", NSNumber(value: -1), NSNumber(value: 42)]
        #expect(PhotoKitAssetSizeEstimator.totalSize(of: values) == 42)
    }

    @Test func noKnownSizeIsUnavailable() {
        #expect(PhotoKitAssetSizeEstimator.totalSize(of: []) == nil)
        #expect(PhotoKitAssetSizeEstimator.totalSize(of: [nil, "x"]) == nil)
    }

    @Test func unknownIDsGiveNoSize() async {
        let estimator = PhotoKitAssetSizeEstimator()
        #expect(await estimator.estimatedSizes(of: []).isEmpty)
    }
}
