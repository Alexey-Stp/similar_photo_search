import Domain
import Foundation

/// `AssetDeletionService` that records requests and returns a preset outcome.
public actor MockAssetDeletionService: AssetDeletionService {
    /// Outcome returned by every call.
    public let outcome: DeletionOutcome
    /// Asset IDs passed to each call.
    public private(set) var deletionRequests: [[String]] = []

    /// Creates the mock.
    public init(outcome: DeletionOutcome = .deleted) {
        self.outcome = outcome
    }

    public func delete(assetIDs: [String]) -> DeletionOutcome {
        deletionRequests.append(assetIDs)
        return outcome
    }
}
