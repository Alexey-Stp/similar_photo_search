import Domain
import DomainTestSupport
import Foundation
import Testing

/// The calibration fixture format and the anonymizing builder (SPS-28).
struct CalibrationFixtureTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000.125)

    static func asset(_ id: String, seconds: TimeInterval?, burst: String? = nil) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: seconds.map { start.addingTimeInterval($0) },
            pixelWidth: 4032,
            pixelHeight: 3024,
            isFavorite: false,
            mediaSubtypes: [],
            burstIdentifier: burst
        )
    }

    static func sample(
        _ album: String,
        _ id: String,
        seconds: TimeInterval?,
        burst: String? = nil,
        printFor printID: String? = nil
    ) -> CalibrationFixtureBuilder.Sample {
        CalibrationFixtureBuilder.Sample(
            albumName: album,
            asset: asset(id, seconds: seconds, burst: burst),
            featurePrint: FeaturePrint(
                assetID: printID ?? id,
                revision: 2,
                vector: [Float(seconds ?? 0), -0.0, 1],
                assetModificationDate: nil
            )
        )
    }

    // MARK: - Format

    @Test func roundTripKeepsEveryBitOfTheVectorAndTheDate() throws {
        let photo = CalibrationPhoto(
            id: "p0001",
            group: "burst-g1",
            category: .burst,
            creationDate: Self.start,
            burstIdentifier: "b1",
            revision: 2,
            vector: [1, -0.0, .leastNonzeroMagnitude, .greatestFiniteMagnitude, -3.25]
        )
        let fixture = CalibrationFixture(source: "test", photos: [photo])

        let decoded = try CalibrationFixture.decoded(from: fixture.encoded())

        #expect(decoded == fixture)
        #expect(decoded.photos[0].vector.map(\.bitPattern) == photo.vector.map(\.bitPattern))
    }

    @Test func vectorIsBase64OfLittleEndianFloats() throws {
        let photo = CalibrationPhoto(
            id: "p0001",
            group: "unrelated-g1",
            category: .unrelated,
            creationDate: Self.start,
            burstIdentifier: nil,
            revision: 2,
            vector: [1]
        )
        let encoded = try CalibrationFixture(source: "x", photos: [photo]).encoded()
        let json = try #require(String(data: encoded, encoding: .utf8))

        // 1.0 is 0x3F800000, so its little-endian bytes are 00 00 80 3F.
        #expect(json.contains("\"vector\" : \"AACAPw==\""))
        #expect(!json.contains("burstIdentifier"))
        #expect(json.hasSuffix("}\n"))
    }

    @Test func decodingRejectsAnotherFormatVersion() throws {
        let json = Data(#"{"formatVersion": 2, "source": "x", "photos": []}"#.utf8)

        #expect(throws: DecodingError.self) { try CalibrationFixture.decoded(from: json) }
    }

    @Test func decodingRejectsAVectorThatIsNotWholeFloats() throws {
        let json = Data("""
            {"formatVersion": 1, "source": "x", "photos": [{"id": "p1", "group": "g", "category": "burst",
            "creationDate": 0, "revision": 2, "vector": "AACA"}]}
            """.utf8)

        #expect(throws: DecodingError.self) { try CalibrationFixture.decoded(from: json) }
    }

    // MARK: - Album names

    @Test(arguments: [
        ("burst--dog jumping", CalibrationCategory.burst, "dog jumping"),
        ("Low-Light -- city at night", .lowLight, "city at night"),
        ("different-subject--park--left", .differentSubject, "park--left")
    ])
    func parsesAlbumNames(name: String, category: CalibrationCategory, label: String) throws {
        let parsed = try #require(CalibrationFixtureBuilder.parseAlbumName(name))

        #expect(parsed.category == category)
        #expect(parsed.label == label)
    }

    @Test(arguments: ["burst", "burst--", "selfies--beach", "--beach", "burst-beach"])
    func rejectsAlbumNamesOutsideTheConvention(name: String) {
        #expect(CalibrationFixtureBuilder.parseAlbumName(name) == nil)
    }

    // MARK: - Builder

    @Test func builderAnonymizesIDsBurstsAndGroupsInDateOrder() throws {
        let samples = [
            Self.sample("burst--Anna on the swing", "LOCAL-C", seconds: 2, burst: "BURST-X"),
            Self.sample("burst--Anna on the swing", "LOCAL-A", seconds: 1, burst: "BURST-X"),
            Self.sample("document--receipts", "LOCAL-B", seconds: 5),
            Self.sample("unrelated--street", "LOCAL-D", seconds: 3),
            Self.sample("unrelated--street", "LOCAL-E", seconds: 4)
        ]

        let fixture = try CalibrationFixtureBuilder().fixture(from: samples, source: "iPhone / iOS")

        #expect(fixture.photos.map(\.id) == ["p0001", "p0002", "p0003", "p0004", "p0005"])
        #expect(fixture.photos.map(\.vector.first) == [1, 2, 3, 4, 5])
        #expect(fixture.photos.map(\.burstIdentifier) == ["b1", "b1", nil, nil, nil])
        #expect(fixture.photos.map(\.group) == [
            "burst-g1", "burst-g1", "unrelated-g2", "unrelated-g3", "document-g4"
        ])
        #expect(fixture.photos.map(\.category) == [.burst, .burst, .unrelated, .unrelated, .document])
        #expect(fixture.photos[0].creationDate == Self.start.addingTimeInterval(1))

        let json = try #require(String(data: fixture.encoded(), encoding: .utf8))
        for secret in ["LOCAL", "BURST-X", "Anna", "receipts", "street"] {
            #expect(!json.contains(secret), "\(secret) leaked into the fixture")
        }
    }

    @Test func builderRejectsAPhotoInTwoAlbums() {
        let samples = [
            Self.sample("burst--one", "LOCAL-A", seconds: 1),
            Self.sample("reframed--two", "LOCAL-A", seconds: 1)
        ]

        #expect(throws: CalibrationFixtureBuilder.BuildError.photoInSeveralAlbums(
            albumNames: ["burst--one", "reframed--two"]
        )) {
            try CalibrationFixtureBuilder().fixture(from: samples, source: "x")
        }
    }

    @Test func builderRejectsBadAlbumsMissingDatesAndForeignPrints() {
        let builder = CalibrationFixtureBuilder()

        #expect(throws: CalibrationFixtureBuilder.BuildError.invalidAlbumName("holiday")) {
            try builder.fixture(from: [Self.sample("holiday", "LOCAL-A", seconds: 1)], source: "x")
        }
        #expect(throws: CalibrationFixtureBuilder.BuildError.missingCreationDate(albumName: "burst--one")) {
            try builder.fixture(from: [Self.sample("burst--one", "LOCAL-A", seconds: nil)], source: "x")
        }
        #expect(throws: CalibrationFixtureBuilder.BuildError.mismatchedFeaturePrint(albumName: "burst--one")) {
            let foreignPrint = Self.sample("burst--one", "LOCAL-A", seconds: 1, printFor: "LOCAL-Z")
            return try builder.fixture(from: [foreignPrint], source: "x")
        }
    }
}
