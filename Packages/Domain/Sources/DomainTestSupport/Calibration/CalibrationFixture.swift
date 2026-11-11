import Domain
import Foundation

/// The labelled calibration set (SPS-28): one entry per photo with its feature print, date, burst and group label.
///
/// It holds **no image pixels**, only vectors, so no personal photo is committed. It is built on a physical device
/// (`CalibrationFixtureBuilder`, from the debug-only extraction test in `DataTests`) and read by the calibration
/// test in `DomainTests`.
public struct CalibrationFixture: Sendable, Hashable, Codable {
    /// The format this code writes and reads.
    public static let currentFormatVersion = 1

    /// The fixture's format; a different value is rejected when decoding.
    public let formatVersion: Int
    /// Where the vectors came from, for example `"iPhone15,2 / iOS 18.1"`. Never a person's name.
    public let source: String
    /// The photos, oldest first.
    public let photos: [CalibrationPhoto]

    /// Creates a fixture in the current format.
    public init(source: String, photos: [CalibrationPhoto]) {
        formatVersion = Self.currentFormatVersion
        self.source = source
        self.photos = photos
    }

    /// Decodes a fixture; throws `DecodingError` for any format other than `currentFormatVersion`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == Self.currentFormatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .formatVersion,
                in: container,
                debugDescription: "Unsupported calibration fixture format \(formatVersion)"
            )
        }
        source = try container.decode(String.self, forKey: .source)
        photos = try container.decode([CalibrationPhoto].self, forKey: .photos)
    }

    /// The fixture as JSON: sorted keys, one line per photo field, dates as seconds since 1970.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    /// A fixture decoded from `encoded()` output.
    public static func decoded(from data: Data) throws -> CalibrationFixture {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(CalibrationFixture.self, from: data)
    }
}

/// One labelled photo of the calibration set.
public struct CalibrationPhoto: Sendable, Hashable, Codable {
    /// An anonymous ID (`p0001`, …), not the PhotoKit `localIdentifier`.
    public let id: String
    /// Photos with the same group are "the same picture"; every other pair is "not the same".
    public let group: String
    /// What kind of photos the group holds, for the coverage check.
    public let category: CalibrationCategory
    /// When the photo was taken.
    public let creationDate: Date
    /// An anonymous burst ID (`b1`, …); equal for photos of the same burst.
    public let burstIdentifier: String?
    /// The Vision revision of `vector`.
    public let revision: Int
    /// The feature-print vector, stored as base64 of little-endian `Float`s (the cache's packed bytes).
    public let vector: [Float]

    /// Creates a photo.
    public init(
        id: String,
        group: String,
        category: CalibrationCategory,
        creationDate: Date,
        burstIdentifier: String?,
        revision: Int,
        vector: [Float]
    ) {
        self.id = id
        self.group = group
        self.category = category
        self.creationDate = creationDate
        self.burstIdentifier = burstIdentifier
        self.revision = revision
        self.vector = vector
    }

    /// The photo as the clustering engine sees it.
    public var vectorItem: VectorItem {
        VectorItem(id: id, date: creationDate, burstID: burstIdentifier, revision: revision, vector: vector)
    }

    /// The photo as the session segmenter sees it (metadata only; size and flags don't matter there).
    public var photoAsset: PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: creationDate,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: [],
            burstIdentifier: burstIdentifier
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, group, category, creationDate, burstIdentifier, revision, vector
    }

    /// Decodes a photo; throws `DecodingError` if `vector` is not base64 of whole little-endian `Float`s.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        group = try container.decode(String.self, forKey: .group)
        category = try container.decode(CalibrationCategory.self, forKey: .category)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        burstIdentifier = try container.decodeIfPresent(String.self, forKey: .burstIdentifier)
        revision = try container.decode(Int.self, forKey: .revision)
        let base64 = try container.decode(String.self, forKey: .vector)
        guard let bytes = Data(base64Encoded: base64), let vector = CalibrationVectorCoding.vector(from: bytes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .vector,
                in: container,
                debugDescription: "Vector is not base64 of whole little-endian Floats"
            )
        }
        self.vector = vector
    }

    /// Encodes the photo with `vector` as base64 of little-endian `Float`s and no `burstIdentifier` key when nil.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(group, forKey: .group)
        try container.encode(category, forKey: .category)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(burstIdentifier, forKey: .burstIdentifier)
        try container.encode(revision, forKey: .revision)
        try container.encode(CalibrationVectorCoding.data(from: vector).base64EncodedString(), forKey: .vector)
    }
}

/// The kinds of photos the calibration set must cover (SPS-28 acceptance criteria).
public enum CalibrationCategory: String, Sendable, Hashable, Codable, CaseIterable {
    /// Burst shots.
    case burst
    /// The same scene, re-framed (zoom, step aside, portrait vs landscape).
    case reframed
    /// The same scene with a different subject: each subject is its own group.
    case differentSubject = "different-subject"
    /// Screenshots.
    case screenshot
    /// Documents and receipts.
    case document
    /// Night and low-light shots.
    case lowLight = "low-light"
    /// Unrelated photos taken within a few minutes of each other: every photo is its own group.
    case unrelated
}

/// Packs vectors as little-endian `Float` bytes, independent of the host's byte order.
enum CalibrationVectorCoding {
    /// The little-endian bytes of `vector`, 4 per value.
    static func data(from vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * 4)
        for value in vector {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// The vector stored in `data`, or `nil` if its size is not a whole number of `Float`s.
    static func vector(from data: Data) -> [Float]? {
        guard data.count.isMultiple(of: 4) else { return nil }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            let bits = UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
            return Float(bitPattern: bits)
        }
    }
}
