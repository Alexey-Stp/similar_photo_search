import Domain
import Foundation

/// SwiftData-backed feature-print cache written through a `@ModelActor`. Placeholder until the cache ticket.
public actor SwiftDataFeaturePrintCache: FeaturePrintCache {
    /// Creates the cache.
    public init() {}

    public func cachedFeaturePrint(
        for assetID: String,
        revision: Int,
        modificationDate: Date?
    ) async -> FeaturePrint? {
        fatalError("Not implemented")
    }

    public func store(_ featurePrint: FeaturePrint) async throws {
        fatalError("Not implemented")
    }
}
