import Domain
import Foundation

/// Turns labelled photos from a device into an anonymous `CalibrationFixture`.
///
/// Labelling convention: every album in the calibration folder is one group, named `<category>--<label>`, for
/// example `burst--dog-jumping` or `document--receipts-cafe`. `<category>` is a `CalibrationCategory` raw value.
/// In an `unrelated--…` album every photo is its own group.
///
/// Neither PhotoKit IDs nor album titles reach the fixture: photos become `p0001`, … in date order; bursts `b1`, …
/// and groups `<category>-g1`, … in order of first use.
public struct CalibrationFixtureBuilder: Sendable {
    /// Separates the category from the label in an album name.
    public static let albumNameSeparator = "--"

    /// One photo of a calibration album together with its feature print.
    public struct Sample: Sendable, Hashable {
        /// The title of the album the photo is in.
        public let albumName: String
        /// The photo.
        public let asset: PhotoAsset
        /// Its feature print.
        public let featurePrint: FeaturePrint

        /// Creates a sample.
        public init(albumName: String, asset: PhotoAsset, featurePrint: FeaturePrint) {
            self.albumName = albumName
            self.asset = asset
            self.featurePrint = featurePrint
        }
    }

    /// Why the samples can't become a fixture.
    public enum BuildError: Error, Sendable, Hashable {
        /// The album name is not `<category>--<label>` with a known category and a non-empty label.
        case invalidAlbumName(String)
        /// The photo is in two albums, so its label is ambiguous. Carries both album names.
        case photoInSeveralAlbums(albumNames: [String])
        /// The photo has no creation date, so it would never be in a session.
        case missingCreationDate(albumName: String)
        /// The feature print belongs to another photo.
        case mismatchedFeaturePrint(albumName: String)
    }

    /// Creates a builder.
    public init() {}

    /// The category and label of an album name, or `nil` if it doesn't follow the convention.
    public static func parseAlbumName(_ name: String) -> (category: CalibrationCategory, label: String)? {
        guard let range = name.range(of: albumNameSeparator) else { return nil }
        let rawCategory = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        let label = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let category = CalibrationCategory(rawValue: rawCategory), !label.isEmpty else { return nil }
        return (category, label)
    }

    /// The fixture for `samples`, photos oldest first.
    public func fixture(from samples: [Sample], source: String) throws(BuildError) -> CalibrationFixture {
        let labelled = try labelledSamples(samples)
        let ordered = labelled.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.sample.asset.id < rhs.sample.asset.id
        }
        var burstAliases = AliasTable(prefix: "b")
        var groupAliases = AliasTable(prefix: "g")
        var photos: [CalibrationPhoto] = []
        for (index, entry) in ordered.enumerated() {
            let photoID = String(format: "p%04d", index + 1)
            let burst = entry.sample.asset.burstIdentifier.map { burstAliases.alias(for: $0) }
            // Unrelated photos are each their own group, keyed by the photo instead of the album.
            let groupKey = entry.category == .unrelated ? "\(entry.group)#\(photoID)" : entry.group
            let group = "\(entry.category.rawValue)-\(groupAliases.alias(for: groupKey))"
            photos.append(CalibrationPhoto(
                id: photoID,
                group: group,
                category: entry.category,
                creationDate: entry.date,
                burstIdentifier: burst,
                revision: entry.sample.featurePrint.revision,
                vector: entry.sample.featurePrint.vector
            ))
        }
        return CalibrationFixture(source: source, photos: photos)
    }

    /// Replaces original strings with `<prefix>1`, `<prefix>2`, … in order of first use.
    private struct AliasTable {
        let prefix: String
        private var aliases: [String: String] = [:]

        init(prefix: String) {
            self.prefix = prefix
        }

        mutating func alias(for original: String) -> String {
            if let alias = aliases[original] { return alias }
            let alias = "\(prefix)\(aliases.count + 1)"
            aliases[original] = alias
            return alias
        }
    }

    private struct LabelledSample {
        let sample: Sample
        let category: CalibrationCategory
        let group: String
        let date: Date
    }

    private func labelledSamples(_ samples: [Sample]) throws(BuildError) -> [LabelledSample] {
        var albumByAsset: [String: String] = [:]
        var result: [LabelledSample] = []
        for sample in samples {
            guard let parsed = Self.parseAlbumName(sample.albumName) else {
                throw .invalidAlbumName(sample.albumName)
            }
            if let other = albumByAsset[sample.asset.id] {
                throw .photoInSeveralAlbums(albumNames: [other, sample.albumName].sorted())
            }
            albumByAsset[sample.asset.id] = sample.albumName
            guard let date = sample.asset.creationDate else {
                throw .missingCreationDate(albumName: sample.albumName)
            }
            guard sample.featurePrint.assetID == sample.asset.id else {
                throw .mismatchedFeaturePrint(albumName: sample.albumName)
            }
            let group = "\(parsed.category.rawValue)\(Self.albumNameSeparator)\(parsed.label)"
            result.append(LabelledSample(sample: sample, category: parsed.category, group: group, date: date))
        }
        return result
    }
}
