import Domain
import DomainTestSupport
import Foundation
import Testing

struct SessionSegmenterTests {
    private struct PageError: Error, Equatable {}

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components) else {
            fatalError("Invalid test date")
        }
        return date
    }

    private static func asset(_ id: String, _ date: Date?, burst: String? = nil) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: date,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: [],
            burstIdentifier: burst
        )
    }

    /// A finished stream of `pages`.
    private static func stream(_ pages: [[PhotoAsset]]) -> AsyncThrowingStream<[PhotoAsset], Error> {
        AsyncThrowingStream { continuation in
            for page in pages {
                continuation.yield(page)
            }
            continuation.finish()
        }
    }

    /// All events for a library given as one page (assets are sorted into `libraryOrder` first).
    private static func events(
        _ assets: [PhotoAsset],
        config: SessionConfig = .default,
        logger: MockSessionSegmentationLogger = MockSessionSegmentationLogger()
    ) async throws -> (sessions: [PhotoSession], summary: SessionSegmentationSummary?) {
        let pages = stream([assets.sorted(by: PhotoAsset.libraryOrder)])
        return try await collect(SessionSegmenter(logger: logger).sessions(from: pages, config: config))
    }

    private static func collect(
        _ sequence: SessionSequence
    ) async throws -> (sessions: [PhotoSession], summary: SessionSegmentationSummary?) {
        var sessions: [PhotoSession] = []
        var summary: SessionSegmentationSummary?
        for try await event in sequence {
            switch event {
            case .session(let session):
                #expect(summary == nil, "No session may follow the summary")
                sessions.append(session)
            case .finished(let finished):
                summary = finished
            }
        }
        return (sessions, summary)
    }

    // MARK: - Gap rule

    @Test func splitsAtGapLargerThanSessionGap() async throws {
        let result = try await Self.events([
            Self.asset("a", Self.date(9, 10, 0)),
            Self.asset("b", Self.date(9, 10, 5)),
            Self.asset("c", Self.date(9, 10, 40))
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["c"], ["b", "a"]])
        #expect(result.sessions.map(\.needsAnalysis) == [false, true])
        let older = try #require(result.sessions.last)
        #expect(older.dateRange == Self.date(9, 10, 0)...Self.date(9, 10, 5))
        #expect(result.summary?.sessionCount == 2)
        #expect(result.summary?.singlePhotoSessionCount == 1)
    }

    @Test func midnightDoesNotSplitASession() async throws {
        let result = try await Self.events([
            Self.asset("late", Self.date(8, 23, 55)),
            Self.asset("early", Self.date(9, 0, 5))
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["early", "late"]])
    }

    @Test func photosOnDifferentDaysAreNeverTogether() async throws {
        let result = try await Self.events([
            Self.asset("monday", Self.date(9, 12, 0)),
            Self.asset("tuesday", Self.date(10, 12, 0))
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["tuesday"], ["monday"]])
        #expect(result.sessions.allSatisfy { !$0.needsAnalysis })
    }

    @Test func gapEqualToSessionGapKeepsTheSession() async throws {
        let base = Self.date(9, 10, 0)
        let result = try await Self.events([
            Self.asset("a", base),
            Self.asset("b", base.addingTimeInterval(900)),
            Self.asset("c", base.addingTimeInterval(1_800.001))
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["c"], ["b", "a"]])
    }

    @Test(arguments: SessionGapPreset.allCases)
    func presetsDecideTheGap(preset: SessionGapPreset) async throws {
        // 10 minutes apart: together only when the gap is at least 10 minutes.
        let result = try await Self.events(
            [Self.asset("a", Self.date(9, 10, 0)), Self.asset("b", Self.date(9, 10, 10))],
            config: SessionConfig(sessionGap: preset.interval)
        )
        #expect(result.sessions.count == (preset == .strict ? 2 : 1))
    }

    @Test func sessionsContinueAcrossPages() async throws {
        let pages = [
            [Self.asset("a", Self.date(9, 10, 20)), Self.asset("b", Self.date(9, 10, 15))],
            [Self.asset("c", Self.date(9, 10, 10))],
            [Self.asset("d", Self.date(9, 9, 0))]
        ]
        let result = try await Self.collect(SessionSegmenter().sessions(from: Self.stream(pages)))
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["a", "b", "c"], ["d"]])
    }

    // MARK: - Bursts and equal timestamps

    @Test func burstWithEqualTimestampsIsOneSession() async throws {
        let shot = Self.date(9, 10, 0)
        let result = try await Self.events([
            Self.asset("b3", shot, burst: "burst"),
            Self.asset("b1", shot, burst: "burst"),
            Self.asset("b2", shot, burst: "burst"),
            Self.asset("other", shot)
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["b1", "b2", "b3", "other"]])
    }

    @Test func burstFrameWithEditedDateBeyondTheGapIsSeparate() async throws {
        let result = try await Self.events([
            Self.asset("b1", Self.date(9, 10, 0), burst: "burst"),
            Self.asset("b2", Self.date(9, 10, 0, 1), burst: "burst"),
            Self.asset("b3-edited", Self.date(9, 14, 0), burst: "burst")
        ])
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["b3-edited"], ["b2", "b1"]])
    }

    // MARK: - Missing dates

    @Test func photosWithoutDateAreCountedNotSessioned() async throws {
        let logger = MockSessionSegmentationLogger()
        let result = try await Self.events(
            [
                Self.asset("a", Self.date(9, 10, 0)),
                Self.asset("b", Self.date(9, 10, 1)),
                Self.asset("undated-1", nil),
                Self.asset("undated-2", nil)
            ],
            logger: logger
        )
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["b", "a"]])
        #expect(result.summary?.skippedNoDateCount == 2)
        let summary = try #require(result.summary)
        #expect(logger.summaries == [summary])
    }

    @Test func onlyUndatedPhotosGiveNoSessions() async throws {
        let result = try await Self.events([Self.asset("x", nil)])
        #expect(result.sessions.isEmpty)
        #expect(result.summary == SessionSegmentationSummary(skippedNoDateCount: 1))
    }

    @Test func emptyInputFinishesWithEmptySummary() async throws {
        let result = try await Self.collect(SessionSegmenter().sessions(from: Self.stream([])))
        #expect(result.sessions.isEmpty)
        #expect(result.summary == SessionSegmentationSummary())
    }

    // MARK: - maxSessionSize

    @Test func oversizedSessionIsSplitAtLargestGapAndLogged() async throws {
        let base = Self.date(9, 10, 0)
        // Newest first: 3 photos 1 s apart, a 60 s gap, then 3 photos 1 s apart. All within 15 min.
        let offsets: [TimeInterval] = [0, 1, 2, 62, 63, 64]
        let assets = offsets.enumerated().map { Self.asset("p\($0.offset)", base.addingTimeInterval(-$0.element)) }
        let logger = MockSessionSegmentationLogger()
        let result = try await Self.events(assets, config: SessionConfig(maxSessionSize: 4), logger: logger)
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["p0", "p1", "p2"], ["p3", "p4", "p5"]])
        #expect(logger.splits.map(\.assetCount) == [6])
        #expect(logger.splits.map(\.partSizes) == [[3, 3]])
        #expect(result.summary?.oversizedSplitCount == 1)
    }

    @Test func splittingRecursesUntilEveryPartFits() async throws {
        let base = Self.date(9, 10, 0)
        // Gaps (newest first): 1, 5, 1, 3, 1. Max 2 → cut at 5, then at 3 → [2] [2] [2].
        let offsets: [TimeInterval] = [0, 1, 6, 7, 10, 11]
        let assets = offsets.enumerated().map { Self.asset("p\($0.offset)", base.addingTimeInterval(-$0.element)) }
        let logger = MockSessionSegmentationLogger()
        let result = try await Self.events(assets, config: SessionConfig(maxSessionSize: 2), logger: logger)
        #expect(result.sessions.map { $0.assets.map(\.id) } == [["p0", "p1"], ["p2", "p3"], ["p4", "p5"]])
        #expect(logger.splits.map(\.partSizes) == [[2, 2, 2]])
    }

    @Test func runWithoutGapIsChunkedInLibraryOrder() async throws {
        let shot = Self.date(9, 10, 0)
        let assets = (0..<501).map { Self.asset("id" + String(1_000 + $0), shot) }
        let logger = MockSessionSegmentationLogger()
        let result = try await Self.events(Array(assets.reversed()), logger: logger)
        #expect(result.sessions.map(\.assets.count) == [500, 1])
        #expect(result.sessions.flatMap(\.assets).map(\.id) == assets.map(\.id))
        #expect(Set(result.sessions.map(\.id)).count == 2)
        #expect(result.sessions.map(\.needsAnalysis) == [true, false])
        #expect(logger.splits.map(\.partSizes) == [[500, 1]])
    }

    // MARK: - Streaming and cancellation

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

    @Test func cancellingTheConsumerStopsSegmentation() async throws {
        let (pages, continuation) = AsyncThrowingStream.makeStream(of: [PhotoAsset].self, throwing: Error.self)
        continuation.yield([Self.asset("a", Self.date(9, 12, 0))])
        let sequence = SessionSegmenter().sessions(from: pages)
        let consumer = Task {
            var count = 0
            for try await _ in sequence {
                count += 1
            }
            return count
        }
        consumer.cancel()
        // The input never finishes on its own; only cancellation can end the loop.
        await #expect(throws: CancellationError.self) {
            _ = try await consumer.value
        }
        continuation.finish()
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
        let config = SessionConfig(sessionGap: -1, maxSessionSize: 0)
        #expect(config.sessionGap == 0)
        #expect(config.maxSessionSize == 1)
        #expect(SessionConfig.default == SessionConfig(sessionGap: 900, maxSessionSize: 500))
    }

    @Test func presetIntervals() {
        #expect(SessionGapPreset.allCases.map(\.interval) == [300, 900, 3_600])
    }
}
