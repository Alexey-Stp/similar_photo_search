import Domain
import Foundation

/// `SessionSegmentationLogging` that records every call, for tests.
///
/// The protocol is synchronous, so the records are guarded by a lock instead of an actor.
public final class MockSessionSegmentationLogger: SessionSegmentationLogging, @unchecked Sendable {
    /// One recorded oversized-session split.
    public struct Split: Sendable, Hashable {
        /// Size of the run before splitting.
        public let assetCount: Int
        /// Sizes of the resulting sessions, newest first.
        public let partSizes: [Int]
    }

    private let lock = NSLock()
    private var recordedSplits: [Split] = []
    private var recordedSummaries: [SessionSegmentationSummary] = []

    /// Creates the mock.
    public init() {}

    /// Splits reported so far, in order.
    public var splits: [Split] {
        lock.withLock { recordedSplits }
    }

    /// Summaries reported so far, in order.
    public var summaries: [SessionSegmentationSummary] {
        lock.withLock { recordedSummaries }
    }

    public func didSplitOversizedSession(assetCount: Int, partSizes: [Int]) {
        lock.withLock { recordedSplits.append(Split(assetCount: assetCount, partSizes: partSizes)) }
    }

    public func didFinish(_ summary: SessionSegmentationSummary) {
        lock.withLock { recordedSummaries.append(summary) }
    }
}
