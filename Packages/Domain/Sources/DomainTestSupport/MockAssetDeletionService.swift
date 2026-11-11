import Domain
import Foundation

/// `AssetDeletionService` that records requests and answers with a scripted result.
public actor MockAssetDeletionService: AssetDeletionService {
    /// Builds the result for the requested IDs.
    public typealias Responder = @Sendable ([String]) -> DeletionResult

    private let respond: Responder
    /// Asset IDs passed to each call.
    public private(set) var deletionRequests: [[String]] = []

    /// Creates the mock. By default every requested ID is deleted.
    public init(respond: @escaping Responder = { DeletionResult(deleted: Set($0)) }) {
        self.respond = respond
    }

    /// Creates a mock that returns `result` for every call.
    public init(result: DeletionResult) {
        self.init { _ in result }
    }

    public func delete(assetIDs: [String]) -> DeletionResult {
        deletionRequests.append(assetIDs)
        return respond(assetIDs)
    }
}
