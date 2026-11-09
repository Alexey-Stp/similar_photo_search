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
        func increment() { count += 1 }
    }

    private static func count(_ stream: AsyncStream<Void>) -> (Counter, Task<Void, Never>) {
        let counter = Counter()
        let task = Task {
            for await _ in stream {
                await counter.increment()
            }
        }
        return (counter, task)
    }

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

    @Test func streamsAfterFinishAreFinishedAndSignalsAreIgnored() async {
        let signal = DebouncedSignal(interval: Self.interval)
        signal.finish()
        signal.signal()
        var iterator = signal.stream().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
