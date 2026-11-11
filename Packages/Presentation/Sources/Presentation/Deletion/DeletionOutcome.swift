import Domain
import Foundation

/// What a deletion did, for the result screen: "Deleted 40 of 45. 5 couldn't be deleted (shared album)".
public struct DeletionOutcome: Sendable, Hashable {
    /// One photo that was not deleted, with the reason.
    public struct Failure: Sendable, Hashable, Identifiable {
        /// The photo's asset ID.
        public let id: String
        /// Why it was not deleted.
        public let reason: DeletionError

        /// Creates a failure.
        public init(id: String, reason: DeletionError) {
            self.id = id
            self.reason = reason
        }

        /// The reason as a short phrase, for example "shared album".
        public var reasonText: String { DeletionOutcome.text(for: reason) }
    }

    /// Number of photos the user asked to delete.
    public let requestedCount: Int
    /// Number of photos deleted.
    public let deletedCount: Int
    /// The estimated size of the deleted photos (`DeletionSummary` of the deleted IDs).
    public let freed: DeletionSummary
    /// The photos that were not deleted, in request order.
    public let failures: [Failure]

    /// Creates an outcome.
    public init(requestedCount: Int, deletedCount: Int, freed: DeletionSummary, failures: [Failure]) {
        self.requestedCount = requestedCount
        self.deletedCount = deletedCount
        self.freed = freed
        self.failures = failures
    }

    /// "Deleted 38 photos (~214 MB). The space is freed when Recently Deleted is emptied."
    public var successText: String {
        guard let bytes = freed.estimatedBytes else {
            return String(localized: "deletion.success.noSize \(deletedCount)", bundle: .module)
        }
        let size = bytes.formatted(.byteCount(style: .file))
        return String(localized: "deletion.success \(deletedCount) \(size)", bundle: .module)
    }

    /// "Deleted 40 of 45. 5 couldn't be deleted (shared album)"; without the reason when the reasons differ.
    public var partialText: String {
        let reasons = Set(failures.map(\.reasonText))
        if reasons.count == 1, let reason = reasons.first {
            return String(
                localized: "deletion.partial \(deletedCount) \(requestedCount) \(failures.count) \(reason)",
                bundle: .module
            )
        }
        return String(
            localized: "deletion.partial.mixed \(deletedCount) \(requestedCount) \(failures.count)",
            bundle: .module
        )
    }

    /// A reason as a short phrase.
    static func text(for reason: DeletionError) -> String {
        switch reason {
        case .notDeletable:
            String(localized: "deletion.reason.notDeletable", bundle: .module)
        case .unavailable:
            String(localized: "deletion.reason.unavailable", bundle: .module)
        case .permissionDenied:
            String(localized: "deletion.reason.permissionDenied", bundle: .module)
        case .notDeleted:
            String(localized: "deletion.reason.notDeleted", bundle: .module)
        case .unknown:
            String(localized: "deletion.reason.unknown", bundle: .module)
        }
    }
}
