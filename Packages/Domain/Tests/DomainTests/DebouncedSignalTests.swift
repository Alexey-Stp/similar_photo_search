import Domain
import Foundation
import Testing

/// Timing tests with a short interval. A burst of synchronous `signal()` calls takes microseconds, far below the
/// interval, and the waits are several intervals long, so the assertions hold on a loaded CI machine.
struct DebouncedSignalTests {
    private static let interval = Duration.milliseconds(100)

    /// Counts the events of `stream` in the background.
    private actor Counter {
        private(set) var count = 0
        /// Adds one event.
        func increment() { count += 1 }
    }

    /// Starts counting the events of `stream`; returns the counter and the counting task.
    private static func count(_ stream: AsyncStream<Void>) -> (Counter, Task<Void, Never>) {
        let counter = Counter()
        let task = Task {
            for await _ in stream {
                await counter.increment()
            }
        }
        return (counter, task)
    }

    /// Twenty signals in a row give one event.
    @Test func aBurstOfSignalsGivesOneEvent() async throws {
        let signal = DebouncedSignal(interval: Self.interval)
        let (counter, task) = Self.count(signal.stream())
        for _ in 0..<20 {
            signal.signal()
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.count == 1)
        signal.finish()
        await task.value
    }

    /// A signal during the quiet period moves the deadline: nothing fires at the original deadline, one event after
    /// the restarted one. 400 ms interval, so each check has 100 ms of slack against scheduler delays.
    @Test func aLaterSignalRestartsTheQuietPeriod() async throws {
        let signal = DebouncedSignal(interval: .milliseconds(400))
        let (counter, task) = Self.count(signal.stream())
        signal.signal()                                  // deadline 400 ms
        try await Task.sleep(for: .milliseconds(200))
        signal.signal()                                  // deadline moves to about 600 ms
        try await Task.sleep(for: .milliseconds(300))    // about 500 ms: past the original deadline
        #expect(await counter.count == 0)
        try await Task.sleep(for: .milliseconds(500))    // about 1,000 ms: past the restarted deadline
        #expect(await counter.count == 1)
        signal.finish()
        await task.value
    }

    /// Bursts separated by more than the interval give one event each.
    @Test func separateBurstsGiveSeparateEvents() async throws {
        let signal = DebouncedSignal(interval: Self.interval)
        let (counter, task) = Self.count(signal.stream())
        signal.signal()
        try await Task.sleep(for: .milliseconds(500))
        signal.signal()
        signal.signal()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.count == 2)
        signal.finish()
        await task.value
    }

    /// Nothing fires before the interval, and `finish()` drops the pending event.
    @Test func noEventBeforeTheQuietPeriodEnds() async throws {
        let signal = DebouncedSignal(interval: .seconds(10))
        let (counter, task) = Self.count(signal.stream())
        signal.signal()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await counter.count == 0)
        signal.finish()
        await task.value
        #expect(await counter.count == 0, "finish() drops the pending event")
    }

    /// Every open stream receives each event.
    @Test func everyStreamReceivesTheEvent() async throws {
        let signal = DebouncedSignal(interval: Self.interval)
        let (first, firstTask) = Self.count(signal.stream())
        let (second, secondTask) = Self.count(signal.stream())
        signal.signal()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await first.count == 1)
        #expect(await second.count == 1)
        signal.finish()
        await firstTask.value
        await secondTask.value
    }

    /// After `finish()`, new streams end at once and signals are ignored.
    @Test func streamsAfterFinishAreFinishedAndSignalsAreIgnored() async {
        let signal = DebouncedSignal(interval: Self.interval)
        signal.finish()
        signal.signal()
        var iterator = signal.stream().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
