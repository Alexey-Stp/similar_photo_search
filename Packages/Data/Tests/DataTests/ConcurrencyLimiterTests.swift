@testable import DataLayer
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ConcurrencyLimiterTests {
    /// A zero or negative limit still lets one task through instead of deadlocking.
    @Test func aLimitBelowOneIsTreatedAsOne() async {
        #expect(await ConcurrencyLimiter(limit: 0).limit == 1)
    }

    /// A released slot goes straight to a waiting task.
    @Test func releaseHandsTheSlotToTheOldestWaiter() async throws {
        let limiter = ConcurrencyLimiter(limit: 1)
        try await limiter.acquire()

        let waiter = Task { try await limiter.acquire() }
        #expect(await waitForWaiters(1, on: limiter))
        await limiter.release()

        try await waiter.value
        #expect(await limiter.waitingCount == 0)
        await limiter.release()
    }

    /// Waiters are served first in, first out.
    @Test func waitersGetSlotsInTheOrderTheyQueued() async throws {
        let limiter = ConcurrencyLimiter(limit: 1)
        let order = OrderRecorder()
        try await limiter.acquire()

        let first = Task {
            try await limiter.acquire()
            await order.append("first")
        }
        // Cancelling on exit wakes any waiter an early failure left suspended; a finished task ignores it.
        defer { first.cancel() }
        #expect(await waitForWaiters(1, on: limiter))
        let second = Task {
            try await limiter.acquire()
            await order.append("second")
        }
        defer { second.cancel() }
        #expect(await waitForWaiters(2, on: limiter))

        await limiter.release()
        let firstGotTheSlot = await waitUntil { await order.names == ["first"] }
        #expect(firstGotTheSlot)
        #expect(await limiter.waitingCount == 1)

        await limiter.release()
        let secondGotTheSlot = await waitUntil { await order.names == ["first", "second"] }
        #expect(secondGotTheSlot)
        await limiter.release()
    }

    /// Cancelling a waiting task ends its wait within 200 ms and leaks no slot.
    @Test func aCancelledWaiterStopsWaitingAtOnceAndHoldsNoSlot() async throws {
        let limiter = ConcurrencyLimiter(limit: 1)
        try await limiter.acquire()

        let waiter = Task { try await limiter.acquire() }
        #expect(await waitForWaiters(1, on: limiter))
        let cancelledAt = ContinuousClock.now
        waiter.cancel()

        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(ContinuousClock.now - cancelledAt < .milliseconds(200))
        #expect(await limiter.waitingCount == 0)

        // The cancelled waiter took no slot: after one release the limiter is free again.
        await limiter.release()
        try await limiter.acquire()
        await limiter.release()
    }

    /// A task that is already cancelled throws at once instead of queueing.
    @Test func anAlreadyCancelledTaskDoesNotWait() async {
        let limiter = ConcurrencyLimiter(limit: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await limiter.acquire()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await limiter.waitingCount == 0)
    }

    /// Polls until `count` tasks wait on the limiter. Returns whether that happened within 2 s.
    private func waitForWaiters(_ count: Int, on limiter: ConcurrencyLimiter) async -> Bool {
        await waitUntil { await limiter.waitingCount >= count }
    }

    /// Polls `condition` until it holds. Returns whether that happened within 2 s.
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while await !condition() {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}

/// Records the order in which tasks got a slot.
private actor OrderRecorder {
    /// Names in the order they were appended.
    private(set) var names: [String] = []

    /// Appends `name`.
    func append(_ name: String) {
        names.append(name)
    }
}
