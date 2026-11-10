import Domain
import Foundation

/// `ThermalMonitor` whose conditions tests set by hand; every open stream receives each change.
public final class MockThermalMonitor: ThermalMonitor, @unchecked Sendable {
    // @unchecked: every mutable property is guarded by `lock`.
    private let lock = NSLock()
    private var conditions: ScanConditions
    private var continuations: [UInt64: AsyncStream<ScanConditions>.Continuation] = [:]
    private var nextID: UInt64 = 0

    /// Creates the monitor with initial conditions.
    public init(conditions: ScanConditions = .nominal) {
        self.conditions = conditions
    }

    /// The current conditions.
    public func currentConditions() async -> ScanConditions {
        lock.withLock { conditions }
    }

    /// A stream of later changes.
    public func conditionChanges() -> AsyncStream<ScanConditions> {
        let (stream, continuation) = AsyncStream.makeStream(of: ScanConditions.self)
        let id = lock.withLock {
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.continuations[id] = nil }
        }
        return stream
    }

    /// Changes the conditions and tells every open stream.
    public func set(_ newConditions: ScanConditions) {
        let open = lock.withLock {
            conditions = newConditions
            return Array(continuations.values)
        }
        for continuation in open {
            continuation.yield(newConditions)
        }
    }

    /// The number of streams currently open, so tests can wait until a scan listens.
    public var subscriberCount: Int {
        lock.withLock { continuations.count }
    }
}
