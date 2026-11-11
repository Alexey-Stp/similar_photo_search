import Domain
import Foundation

/// Checks that a calibration fixture can measure what SPS-28 asks for, before any number is taken from it.
public enum CalibrationCoverage {
    /// What the fixture lacks, one sentence per problem; empty when it is complete.
    ///
    /// Every category except `unrelated` needs a labelled pair (a group of at least two photos), `different-subject`
    /// needs at least two subjects, `unrelated` at least two photos, each in its own group, and some burst
    /// identifier must be shared by at least two photos. A fixture of singleton groups or isolated burst identifiers
    /// therefore never passes.
    ///
    /// Precision is only meaningful if "not the same" pairs are actually compared: `unrelated` and
    /// `different-subject` photos each need a pair with another group in the same session (`sessionConfig`) and at
    /// most `maxPairInterval` apart, as the engine would compare them.
    public static func problems(
        in fixture: CalibrationFixture,
        minimumPhotos: Int = 500,
        revision: Int = 2,
        sessionConfig: SessionConfig = .default,
        maxPairInterval: TimeInterval = ClusteringConfig.defaultMaxPairInterval
    ) async throws -> [String] {
        let photos = fixture.photos
        var problems: [String] = []
        if photos.count < minimumPhotos {
            problems.append("The set has \(photos.count) photos; it needs at least \(minimumPhotos).")
        }
        if !photos.allSatisfy({ $0.revision == revision }) {
            problems.append("Only revision-\(revision) prints belong in the set.")
        }
        if Set(photos.map(\.vector.count)).count > 1 {
            problems.append("All vectors must have the same length.")
        }
        if Set(photos.map(\.id)).count != photos.count {
            problems.append("Photo IDs must be unique.")
        }
        problems += categoryProblems(photos)
        if !hasSharedBurst(photos) {
            problems.append("No burst identifier is shared by two photos, so burst slack is never measured.")
        }
        let sessions = try await CalibrationEvaluator(fixture: fixture).sessions(sessionConfig)
        let compared = categoriesInComparedNegativePairs(sessions, maxPairInterval: maxPairInterval)
        for category in [CalibrationCategory.differentSubject, .unrelated] where !compared.contains(category) {
            problems.append(
                "No \(category.rawValue) photo is compared with another group (same session, within the pair "
                    + "interval), so precision is never tested on it."
            )
        }
        return problems
    }

    /// Categories of the photos in at least one pair of different groups that clustering compares: same session and
    /// at most `maxPairInterval` apart.
    private static func categoriesInComparedNegativePairs(
        _ sessions: [[CalibrationPhoto]],
        maxPairInterval: TimeInterval
    ) -> Set<CalibrationCategory> {
        var categories = Set<CalibrationCategory>()
        for session in sessions {
            let sorted = session.sorted { $0.creationDate < $1.creationDate }
            for (index, first) in sorted.enumerated() {
                for second in sorted[(index + 1)...] {
                    guard second.creationDate.timeIntervalSince(first.creationDate) <= maxPairInterval else { break }
                    if first.group != second.group {
                        categories.insert(first.category)
                        categories.insert(second.category)
                    }
                }
            }
        }
        return categories
    }

    /// Labelled pairs per category, two subjects for `different-subject`, singleton groups for `unrelated`.
    private static func categoryProblems(_ photos: [CalibrationPhoto]) -> [String] {
        var problems: [String] = []
        for category in CalibrationCategory.allCases {
            let members = photos.filter { $0.category == category }
            let groupSizes = Dictionary(grouping: members, by: \.group).values.map(\.count)
            switch category {
            case .unrelated:
                if members.count < 2 {
                    problems.append("Category unrelated needs at least two photos.")
                }
                if groupSizes.contains(where: { $0 >= 2 }) {
                    problems.append("Every unrelated photo needs its own group; some share one.")
                }
            default:
                if !groupSizes.contains(where: { $0 >= 2 }) {
                    problems.append("Category \(category.rawValue) has no labelled pair (a group of two or more).")
                }
                if category == .differentSubject, groupSizes.count < 2 {
                    problems.append("Category different-subject needs at least two subjects (groups).")
                }
            }
        }
        return problems
    }

    /// Whether some burst identifier is shared by two or more photos.
    private static func hasSharedBurst(_ photos: [CalibrationPhoto]) -> Bool {
        let burstSizes = Dictionary(grouping: photos.compactMap(\.burstIdentifier), by: { $0 }).values.map(\.count)
        return burstSizes.contains { $0 >= 2 }
    }
}
