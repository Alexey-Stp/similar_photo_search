import Foundation

/// An async semaphore: at most `limit` holders at a time; the others wait in FIFO order.
///
/// A waiting task that is cancelled stops waiting at once and throws `CancellationError`.
actor ConcurrencyLimiter {
    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    /// The most holders at a time (at least 1).
    let limit: Int
    private var holders = 0
    private var waiters: [Waiter] = []
    private var nextWaiterID = 0

    /// Tasks waiting for a slot.
    var waitingCount: Int { waiters.count }

    /// Creates a limiter. Values below 1 are treated as 1.
    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Waits for a free slot. Every successful `acquire()` must be followed by exactly one `release()`.
    /// - Throws: `CancellationError` if the task is cancelled before it gets a slot (it then holds none).
    func acquire() async throws {
        try Task.checkCancellation()
        if holders < limit {
            holders += 1
            return
        }
        let id = nextWaiterID
        nextWaiterID += 1
        // The continuation is stored before this actor can run `cancelWaiter`, so a cancellation is never lost.
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Frees a slot, handing it straight to the oldest waiter if there is one.
    func release() {
        if waiters.isEmpty {
            holders = max(0, holders - 1)
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    /// Removes a cancelled waiter. Does nothing if it already got a slot.
    private func cancelWaiter(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
