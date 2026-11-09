import Domain
import Foundation

/// `ClusteringEngine` that returns preset clusters and records its input.
///
/// The protocol is synchronous, so the records are guarded by a lock instead of an actor.
public final class MockClusteringEngine: ClusteringEngine, @unchecked Sendable {
    /// One recorded call.
    public struct Call: Sendable, Hashable {
        /// The session items passed in.
        public let session: [VectorItem]
        /// The config passed in.
        public let config: ClusteringConfig

        /// Creates a record, for comparing with `calls`.
        public init(session: [VectorItem], config: ClusteringConfig) {
            self.session = session
            self.config = config
        }
    }

    /// Clusters returned by every call.
    public let result: [SimilarityCluster]
    /// Thrown by every call instead of returning `result`, if set.
    public let error: ClusteringError?

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    /// Creates the mock.
    public init(result: [SimilarityCluster] = [], error: ClusteringError? = nil) {
        self.result = result
        self.error = error
    }

    /// Calls received so far, in order.
    public var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    /// Records the call and returns `result`, or throws `error`.
    public func clusters(
        in session: [VectorItem],
        config: ClusteringConfig
    ) throws(ClusteringError) -> [SimilarityCluster] {
        lock.withLock { recordedCalls.append(Call(session: session, config: config)) }
        if let error { throw error }
        return result
    }
}
