import Domain
import DomainTestSupport
import Foundation
import Testing

/// Streaming, cancellation, session ID and config tests of `SessionSegmenter`.
/// The helpers (`asset`, `date`, `events`, ...) are in SessionSegmenterTests.swift.
extension SessionSegmenterTests {
    // MARK: - Streaming and cancellation

    /// A session closed by a gap is emitted while the input stream is still open; the last one, the summary and
    /// `nil` follow once the input ends.
    @Test func sessionIsEmittedBeforeTheInputEnds() async throws {
        let (pages, continuation) = AsyncThrowingStream.makeStream(of: [PhotoAsset].self, throwing: Error.self)
        var iterator = SessionSegmenter().sessions(from: pages).makeAsyncIterator()
        continuation.yield([Self.asset("a", Self.date(9, 12, 0)), Self.asset("b", Self.date(9, 11, 59))])
        continuation.yield([Self.asset("c", Self.date(9, 9, 0))])
        // The input is still open, yet the first session is already closed by the 3 h gap.
        let first = try await iterator.next()
        guard case .session(let firstSession) = first else {
            Issue.record("Expected the first session, got \(String(describing: first))")
            return
        }
        #expect(firstSession.assets.map(\.id) == ["a", "b"])
        continuation.finish()
        let second = try await iterator.next()
        guard case .session(let last) = second else {
            Issue.record("Expected the last session, got \(String(describing: second))")
            return
        }
        #expect(last.assets.map(\.id) == ["c"])
        guard case .finished = try await iterator.next() else {
            Issue.record("Expected the summary")
            return
        }
        #expect(try await iterator.next() == nil)
    }

    /// Cancelling the consuming task while the segmenter waits for a page ends iteration with `CancellationError`.
    /// Cancellation is sent only after the page request is known to be pending, with a bounded wait.
    @Test func cancellingTheConsumerWhileItWaitsForAPageStopsSegmentation() async throws {
        let (requests, requestSignal) = AsyncStream.makeStream(of: Int.self)
        let counter = RequestCounter()
        let firstPage = [Self.asset("a", Self.date(9, 12, 0))]
        // On-demand input: the first request gets a page, the second one waits until it is cancelled.
        let pages = AsyncThrowingStream<[PhotoAsset], Error>(unfolding: {
            let request = await counter.next()
            requestSignal.yield(request)
            guard request > 0 else { return firstPage }
            try await Task.sleep(for: .seconds(3_600))
            return nil
        })
        let sequence = SessionSegmenter().sessions(from: pages)
        let consumer = Task {
            for try await _ in sequence {}
        }
        // Cancel only once the segmenter is really waiting for the second page; a regression fails here, not hangs.
        let isWaiting = await Self.waitForRequest(1, in: requests, timeout: .seconds(5))
        #expect(isWaiting, "The segmenter never asked for the second page")
        consumer.cancel()
        await #expect(throws: CancellationError.self) {
            try await consumer.value
        }
        requestSignal.finish()
    }

    /// A task that is already cancelled throws `CancellationError` on the first step, before reading any page.
    @Test func cancelledConsumerStopsBeforeReadingAnything() async throws {
        let (pages, continuation) = AsyncThrowingStream.makeStream(of: [PhotoAsset].self, throwing: Error.self)
        continuation.yield([Self.asset("a", Self.date(9, 12, 0))])
        let sequence = SessionSegmenter().sessions(from: pages)
        let consumer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            for try await _ in sequence {}
        }
        await #expect(throws: CancellationError.self) {
            try await consumer.value
        }
        continuation.finish()
    }

    /// Whether request number `number` shows up on `requests` within `timeout`.
    private static func waitForRequest(_ number: Int, in requests: AsyncStream<Int>, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await request in requests where request == number {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func errorsFromTheInputAreRethrown() async throws {
        let pages = AsyncThrowingStream<[PhotoAsset], Error> { continuation in
            continuation.yield([Self.asset("a", Self.date(9, 12, 0))])
            continuation.finish(throwing: PageError())
        }
        await #expect(throws: PageError.self) {
            _ = try await Self.collect(SessionSegmenter().sessions(from: pages))
        }
    }

    // MARK: - IDs

    @Test func sessionIDsAreStableAcrossRuns() async throws {
        let assets = [
            Self.asset("a", Self.date(9, 10, 0)),
            Self.asset("b", Self.date(9, 10, 5)),
            Self.asset("c", Self.date(9, 10, 40))
        ]
        let first = try await Self.events(assets).sessions.map(\.id)
        let second = try await Self.events(Array(assets.reversed())).sessions.map(\.id)
        #expect(first == second)
        #expect(first == [
            PhotoSession.id(newestID: "c", newestDate: Self.date(9, 10, 40)),
            PhotoSession.id(newestID: "b", newestDate: Self.date(9, 10, 5))
        ])
        #expect(first[0] == "c@\(Int64(Self.date(9, 10, 40).timeIntervalSince1970) * 1_000)")
    }

    @Test func sessionRejectsUndatedOrEmptyInput() {
        #expect(PhotoSession(assets: []) == nil)
        #expect(PhotoSession(assets: [Self.asset("a", Self.date(9, 1, 0)), Self.asset("b", nil)]) == nil)
    }

    // MARK: - Config

    @Test func configClampsInvalidValues() {
        var config = SessionConfig(sessionGap: -1, maxSessionSize: 0)
        #expect(config.sessionGap == 0)
        #expect(config.maxSessionSize == 1)
        config.maxSessionSize = -5
        config.sessionGap = -60
        #expect(config.maxSessionSize == 1)
        #expect(config.sessionGap == 0)
        config.maxSessionSize = 20
        #expect(config.maxSessionSize == 20)
        #expect(SessionConfig.default == SessionConfig(sessionGap: 900, maxSessionSize: 500))
    }

    @Test func presetIntervals() {
        #expect(SessionGapPreset.allCases.map(\.interval) == [300, 900, 3_600])
    }
}
