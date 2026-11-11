#if os(iOS) && !targetEnvironment(simulator)
@testable import DataLayer
import Domain
import DomainTestSupport
import Foundation
import Photos
import Testing

private let isExtractionRun = ProcessInfo.processInfo.environment["RUN_CALIBRATION_EXTRACTION"] == "1"

/// Device-only, debug-only: extracts the SPS-28 calibration fixture from labelled albums. It is a test, so it never
/// ships in the app. It reads the albums inside a top-level folder named `SPS-Calibration` (one album per group,
/// named `<category>--<label>`, see `Packages/Domain/Tests/DomainTests/Fixtures/README.md`), computes each photo's
/// feature print with the app's own `VisionFeaturePrintService` (512 px, no network), and writes the anonymous
/// fixture as a test attachment and to the temporary directory.
///
/// Run on an iPhone with full photo-library access and the scheme environment variable `RUN_CALIBRATION_EXTRACTION=1`.
struct CalibrationFixtureExtractionTests {
    static let folderName = "SPS-Calibration"
    static let fileName = "calibration-rev2.json"

    struct Album {
        let name: String
        let assets: [PhotoAsset]
    }

    @Test(.enabled(if: isExtractionRun, "Device-only: extracts the SPS-28 calibration fixture"))
    func extractsTheLabelledCalibrationSet() async throws {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Allow full library access")
        let albums = Self.calibrationAlbums()
        try #require(!albums.isEmpty, "No albums in a top-level folder named \(Self.folderName)")
        let service = VisionFeaturePrintService(images: PhotoKitImageLoader())
        try #require(service.revision == 2, "This device produces revision \(service.revision), not 2")

        var samples: [CalibrationFixtureBuilder.Sample] = []
        var unprinted: [String: Int] = [:]
        for album in albums {
            for asset in album.assets {
                if case .computed(let featurePrint) = try await service.featurePrint(for: asset) {
                    samples.append(.init(albumName: album.name, asset: asset, featurePrint: featurePrint))
                } else {
                    unprinted[album.name, default: 0] += 1
                }
            }
        }

        let fixture = try CalibrationFixtureBuilder().fixture(from: samples, source: Self.sourceDescription())
        let data = try fixture.encoded()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName)
        try data.write(to: url)
        #if compiler(>=6.2)
        Attachment.record(Array(data), named: Self.fileName)
        #endif
        print(CalibrationReport.coverageTable(fixture))
        print("Wrote \(fixture.photos.count) photos to \(url.path)")

        #expect(unprinted.isEmpty, "Photos without a print (keep the originals on the device): \(unprinted)")
        #expect(fixture.photos.count >= 500, "The labelled set needs at least 500 photos")
    }

    /// The albums of the calibration folder with their photos (images only, every frame of a burst).
    static func calibrationAlbums() -> [Album] {
        let topLevel = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        var folders: [PHCollectionList] = []
        topLevel.enumerateObjects { collection, _, _ in
            if let folder = collection as? PHCollectionList, folder.localizedTitle == folderName {
                folders.append(folder)
            }
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeAllBurstAssets = true

        var albums: [Album] = []
        for folder in folders {
            PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, _ in
                guard let album = collection as? PHAssetCollection else { return }
                var assets: [PhotoAsset] = []
                PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
                    assets.append(PhotoKitAssetMapper.asset(from: asset))
                }
                albums.append(Album(name: album.localizedTitle ?? "", assets: assets))
            }
        }
        return albums
    }

    /// The device model identifier and OS version, for example `iPhone15,2 / Version 18.1 (Build 22B83)`.
    static func sourceDescription() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return "\(machine) / \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
#endif
