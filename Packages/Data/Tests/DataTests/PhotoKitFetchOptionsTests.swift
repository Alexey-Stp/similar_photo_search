@testable import DataLayer
import Domain
import Foundation
import Photos
import Testing

struct PhotoKitFetchOptionsTests {
    @Test func fetchesImagesNewestFirstWithoutHiddenAssets() throws {
        let options = PhotoKitFetchOptions.make(scope: .allPhotos)
        #expect(options.includeHiddenAssets == false)
        #expect(options.includeAllBurstAssets == false)
        let sort = try #require(options.sortDescriptors?.first)
        #expect(options.sortDescriptors?.count == 1)
        #expect(sort.key == "creationDate")
        #expect(sort.ascending == false)
        let format = try #require(options.predicate?.predicateFormat)
        #expect(format.contains("mediaType == \(PHAssetMediaType.image.rawValue)"))
    }

    @Test(arguments: [false, true])
    func burstSettingFollowsScope(includeBursts: Bool) {
        let options = PhotoKitFetchOptions.make(scope: ScanScope(includeBursts: includeBursts))
        #expect(options.includeAllBurstAssets == includeBursts)
    }

    @Test func screenshotClauseOnlyWhenExcluding() {
        let excluding = PhotoKitFetchOptions.predicate(for: ScanScope(excludeScreenshots: true)).predicateFormat
        let including = PhotoKitFetchOptions.predicate(for: ScanScope(excludeScreenshots: false)).predicateFormat
        #expect(excluding.contains("mediaSubtypes"))
        #expect(!including.contains("mediaSubtypes"))
    }

    @Test func dateRangeIsInclusive() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let predicate = PhotoKitFetchOptions.predicate(
            for: ScanScope(dateRange: start...end, excludeScreenshots: false)
        )
        func matches(_ seconds: TimeInterval) -> Bool {
            let image = NSNumber(value: PHAssetMediaType.image.rawValue)
            let candidate: NSDictionary = ["mediaType": image, "creationDate": Date(timeIntervalSince1970: seconds)]
            return predicate.evaluate(with: candidate)
        }
        #expect(matches(1_000))
        #expect(matches(1_500))
        #expect(matches(2_000))
        #expect(!matches(999))
        #expect(!matches(2_001))
    }

    @Test func noDateClauseWithoutRange() {
        #expect(!PhotoKitFetchOptions.predicate(for: .allPhotos).predicateFormat.contains("creationDate"))
    }
}

struct PhotoKitAssetMapperTests {
    @Test(arguments: [
        (PHAssetMediaSubtype.photoScreenshot, PhotoSubtype.screenshot),
        (.photoHDR, .hdr),
        (.photoPanorama, .panorama),
        (.photoLive, .livePhoto),
        (.photoDepthEffect, .depthEffect)
    ])
    func mapsEachSubtype(mask: PHAssetMediaSubtype, expected: PhotoSubtype) {
        #expect(PhotoKitAssetMapper.subtypes(from: mask) == [expected])
    }

    @Test func mapsCombinedMasksAndIgnoresUnmodelledFlags() {
        let mask: PHAssetMediaSubtype = [.photoLive, .photoHDR, .videoHighFrameRate]
        #expect(PhotoKitAssetMapper.subtypes(from: mask) == [.livePhoto, .hdr])
        #expect(PhotoKitAssetMapper.subtypes(from: []).isEmpty)
    }
}
