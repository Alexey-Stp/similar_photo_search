@testable import DataLayer
import Foundation
import Testing

struct ConcurrencyLimiterTests {
    @Test func aLimitBelowOneIsTreatedAsOne() async {
        #expect(await ConcurrencyLimiter(limit: 0).limit == 1)
    }

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
        let deadline = ContinuousClock.now + .seconds(2)
        while await limiter.waitingCount < count {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}
