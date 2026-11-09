import Foundation

/// Turns bursts of `signal()` calls into one event per burst, delivered to every open `stream()` once no new signal
/// has arrived for `interval` (a trailing debounce).
///
/// `signal()` is synchronous and may be called from any thread, for example a PhotoKit change callback on a
/// background queue. Consumers hop to their own actor when they read the stream.
public final class DebouncedSignal: @unchecked Sendable {
    // @unchecked: every mutable property is guarded by `lock`.
    private let interval: Duration
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pending: Task<Void, Never>?
    private var continuations: [UInt64: AsyncStream<Void>.Continuation] = [:]
    private var nextStreamID: UInt64 = 0
    private var isFinished = false

    /// Creates a signal that settles after `interval` without new calls.
    public init(interval: Duration) {
        self.interval = interval
    }

    deinit {
        pending?.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// Records a change. Restarts the quiet period; the event fires `interval` after the last call.
    public func signal() {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        pending?.cancel()
        generation &+= 1
        let current = generation
        let interval = interval
        pending = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            self?.fire(generation: current)
        }
    }

    /// A new stream of settled events. Holds at most one undelivered event: a slow consumer sees one, not a backlog.
    /// A stream made after `finish()` is already finished.
    public func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.finish()
            return stream
        }
        let id = nextStreamID
        nextStreamID &+= 1
        continuations[id] = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            self?.removeStream(id)
        }
        return stream
    }

    /// Drops a pending event and finishes every stream. Later signals are ignored.
    public func finish() {
        lock.lock()
        isFinished = true
        pending?.cancel()
        pending = nil
        let open = Array(continuations.values)
        continuations = [:]
        lock.unlock()
        for continuation in open {
            continuation.finish()
        }
    }

    /// Delivers the event of `generation`, unless a newer signal has restarted the quiet period.
    private func fire(generation fired: UInt64) {
        lock.lock()
        guard fired == generation, !isFinished else {
            lock.unlock()
            return
        }
        pending = nil
        let open = Array(continuations.values)
        lock.unlock()
        for continuation in open {
            continuation.yield()
        }
    }

    private func removeStream(_ id: UInt64) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
