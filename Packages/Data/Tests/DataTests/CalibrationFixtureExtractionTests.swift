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
/// feature print with the app's own `VisionFeaturePrintService` (512 px, no network), and records the anonymous
/// fixture as a Swift Testing attachment, to be exported from the Xcode test report.
///
/// Run on an iPhone with full photo-library access and the scheme environment variable `RUN_CALIBRATION_EXTRACTION=1`,
/// built with **Xcode 26 or later** (Swift 6.2): attachments don't exist in Swift Testing before that, and there is no
/// other way to get the file off the device. With an older toolchain the test fails with that message.
struct CalibrationFixtureExtractionTests {
    /// The top-level Photos folder that holds the calibration albums.
    static let folderName = "SPS-Calibration"
    /// The attachment's name, which is also the fixture's file name in the repo.
    static let fileName = "calibration-rev2.json"
    /// The smallest labelled set the calibration accepts.
    static let minimumPhotos = 500

    /// One calibration album: its title and its photos.
    struct Album {
        /// The album title, `<category>--<label>`.
        let name: String
        /// The album's photos (images only, every burst frame).
        let assets: [PhotoAsset]
    }

    /// Extracts the fixture and records it as an attachment; records nothing if any check fails.
    @Test(.enabled(if: isExtractionRun, "Device-only: extracts the SPS-28 calibration fixture"))
    func extractsTheLabelledCalibrationSet() async throws {
        #if compiler(>=6.2)
        let data = try await Self.extractFixture()
        Attachment.record(Array(data), named: Self.fileName)
        #else
        Issue.record("Build with Xcode 26 or later (Swift 6.2): the fixture is exported as a test attachment.")
        #endif
    }

    /// The encoded fixture, after every check passed: each photo has a print, and the set is complete.
    static func extractFixture() async throws -> Data {
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Allow full library access")
        let albums = Self.calibrationAlbums()
        try #require(!albums.isEmpty, "No albums in a top-level folder named \(Self.folderName)")
        let service = VisionFeaturePrintService(images: PhotoKitImageLoader())
        try #require(service.revision == 2, "This device produces revision \(service.revision), not 2")

        var samples: [CalibrationFixtureBuilder.Sample] = []
        var unprintedCount = 0
        for album in albums {
            for asset in album.assets {
                if case .computed(let featurePrint) = try await service.featurePrint(for: asset) {
                    samples.append(.init(albumName: album.name, asset: asset, featurePrint: featurePrint))
                } else {
                    unprintedCount += 1
                }
            }
        }

        // Only a count: album titles may hold personal labels and must not end up in shared test logs.
        try #require(
            unprintedCount == 0,
            "\(unprintedCount) photos got no feature print; keep their originals on the device"
        )

        let fixture = try CalibrationFixtureBuilder().fixture(from: samples, source: sourceDescription())
        print(CalibrationReport.coverageTable(fixture))
        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: minimumPhotos)
        try #require(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        print("Extracted \(fixture.photos.count) photos")
        return try fixture.encoded()
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
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        } ?? "unknown device"
        return "\(machine) / \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
#endif
