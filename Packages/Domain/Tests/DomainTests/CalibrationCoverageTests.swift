import DomainTestSupport
import Foundation
import Testing

/// The coverage gate of the calibration set (SPS-28) on small hand-made fixtures.
struct CalibrationCoverageTests {
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    static func photo(
        _ index: Int,
        _ category: CalibrationCategory,
        group: String,
        burst: String? = nil,
        revision: Int = 2,
        length: Int = 2
    ) -> CalibrationPhoto {
        CalibrationPhoto(
            id: "p\(index)",
            group: group,
            category: category,
            creationDate: start.addingTimeInterval(TimeInterval(index)),
            burstIdentifier: burst,
            revision: revision,
            vector: [Float](repeating: 0.5, count: length)
        )
    }

    /// Two photos in one group for every category, two subjects, two unrelated photos and a shared burst.
    static func completePhotos() -> [CalibrationPhoto] {
        var photos: [CalibrationPhoto] = []
        for category in CalibrationCategory.allCases where category != .unrelated {
            let burst = category == .burst ? "b1" : nil
            photos.append(photo(photos.count, category, group: "\(category.rawValue)-g1", burst: burst))
            photos.append(photo(photos.count, category, group: "\(category.rawValue)-g1", burst: burst))
        }
        photos.append(photo(photos.count, .differentSubject, group: "different-subject-g2"))
        photos.append(photo(photos.count, .unrelated, group: "unrelated-g1"))
        photos.append(photo(photos.count, .unrelated, group: "unrelated-g2"))
        return photos
    }

    /// A complete fixture has no problem.
    @Test func completeFixturePasses() async throws {
        let fixture = CalibrationFixture(source: "test", photos: Self.completePhotos())

        #expect(try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 10) == [])
    }

    /// Only singleton groups and isolated burst identifiers: every category and the burst check fail.
    @Test func singletonGroupsAndIsolatedBurstsFail() async throws {
        let photos = CalibrationCategory.allCases.enumerated().map { index, category in
            Self.photo(index, category, group: "\(category.rawValue)-g\(index)", burst: "b\(index)")
        }

        let fixture = CalibrationFixture(source: "test", photos: photos)
        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 1)

        for category in CalibrationCategory.allCases where category != .unrelated {
            #expect(problems.contains { $0.contains("Category \(category.rawValue) has no labelled pair") })
        }
        #expect(problems.contains { $0.contains("different-subject needs at least two subjects") })
        #expect(problems.contains { $0.contains("unrelated needs at least two photos") })
        #expect(problems.contains { $0.contains("No burst identifier is shared") })
    }

    /// One subject only is not enough for `different-subject`, even with a labelled pair.
    @Test func differentSubjectNeedsTwoSubjects() async throws {
        let photos = Self.completePhotos().filter { $0.group != "different-subject-g2" }

        let fixture = CalibrationFixture(source: "test", photos: photos)
        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 1)

        #expect(problems == ["Category different-subject needs at least two subjects (groups)."])
    }

    /// Size, revision, vector length and ID uniqueness are checked too.
    @Test func sizeRevisionLengthAndIDsAreChecked() async throws {
        var photos = Self.completePhotos()
        photos.append(Self.photo(0, .unrelated, group: "unrelated-g9", revision: 1, length: 3))

        let problems = try await CalibrationCoverage.problems(in: CalibrationFixture(source: "test", photos: photos))

        #expect(problems == [
            "The set has \(photos.count) photos; it needs at least 500.",
            "Only revision-2 prints belong in the set.",
            "All vectors must have the same length.",
            "Photo IDs must be unique."
        ])
    }

    /// Two unrelated photos labelled as one group are "the same", which the category forbids.
    @Test func unrelatedPhotosSharingAGroupFail() async throws {
        let photos = Self.completePhotos().map { photo in
            guard photo.category == .unrelated else { return photo }
            return CalibrationPhoto(
                id: photo.id,
                group: "unrelated-g1",
                category: .unrelated,
                creationDate: photo.creationDate,
                burstIdentifier: nil,
                revision: photo.revision,
                vector: photo.vector
            )
        }

        let fixture = CalibrationFixture(source: "test", photos: photos)
        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 1)

        #expect(problems == ["Every unrelated photo needs its own group; some share one."])
    }

    /// Photos two hours apart are in different sessions: no "not the same" pair is ever compared.
    @Test func negativePairsThatAreNeverComparedFail() async throws {
        let photos = Self.completePhotos().enumerated().map { index, photo in
            CalibrationPhoto(
                id: photo.id,
                group: photo.group,
                category: photo.category,
                creationDate: Self.start.addingTimeInterval(TimeInterval(index) * 2 * 60 * 60),
                burstIdentifier: photo.burstIdentifier,
                revision: photo.revision,
                vector: photo.vector
            )
        }

        let fixture = CalibrationFixture(source: "test", photos: photos)
        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 1)

        #expect(problems.count == 2)
        #expect(problems.contains { $0.hasPrefix("No different-subject photo is compared with another group") })
        #expect(problems.contains { $0.hasPrefix("No unrelated photo is compared with another group") })
    }

    /// A pair in one session but further apart than `maxPairInterval` is not compared either.
    @Test func negativePairsBeyondThePairIntervalDoNotCount() async throws {
        let fixture = CalibrationFixture(source: "test", photos: Self.completePhotos())

        let problems = try await CalibrationCoverage.problems(in: fixture, minimumPhotos: 1, maxPairInterval: 0)

        #expect(problems.count == 2)
    }
}
