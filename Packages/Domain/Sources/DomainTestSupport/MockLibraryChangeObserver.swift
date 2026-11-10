import Domain
import Foundation

/// `LibraryChangeObserving` whose signals tests send by hand.
public final class MockLibraryChangeObserver: LibraryChangeObserving, @unchecked Sendable {
    // @unchecked: every stored property is guarded by `lock`.
    private let lock = NSLock()
    private var continuations: [AsyncStream<Void>.Continuation] = []
    private var callCount = 0

    /// Creates the mock.
    public init() {}

    /// How many streams `changes()` has handed out.
    public var changesCallCount: Int {
        lock.withLock { callCount }
    }

    /// A new stream that receives every later `signal()`.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        lock.withLock {
            callCount += 1
            continuations.append(continuation)
        }
        return stream
    }

    /// Sends one "the library changed" signal to every stream.
    public func signal() {
        let current = lock.withLock { continuations }
        for continuation in current {
            continuation.yield()
        }
    }
}
