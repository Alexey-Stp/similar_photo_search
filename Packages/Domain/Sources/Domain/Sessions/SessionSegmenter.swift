import Foundation

/// Cuts the date-ordered photo stream from `PhotoLibraryRepository.assetPages` into shooting sessions.
///
/// Rules:
/// - Two neighbouring photos are in the same session when their `creationDate`s are at most `sessionGap` apart.
///   Only the gap counts: not the calendar day, and not `burstIdentifier`.
/// - A run larger than `maxSessionSize` is split at its largest internal gap, again and again, until every part
///   fits. A part with no gap left (all timestamps equal) is cut into chunks of `maxSessionSize` in
///   `PhotoAsset.libraryOrder`.
/// - Photos without a `creationDate` are not put into any session; they are counted in the summary.
///
/// The input must be in `PhotoAsset.libraryOrder` (newest first), as the repository guarantees.
public struct SessionSegmenter: Sendable {
    private let logger: any SessionSegmentationLogging

    /// Creates a segmenter.
    /// - Parameter logger: Receives split and summary diagnostics.
    public init(logger: any SessionSegmentationLogging = SilentSessionSegmentationLogger()) {
        self.logger = logger
    }

    /// The sessions in `pages`, newest first, followed by one `.finished` event with the summary.
    ///
    /// The sequence pulls a page only when the consumer asks for an event it can't produce yet, and stops reading a
    /// page at the first session boundary: a session is emitted as soon as a later photo shows a gap larger than
    /// `sessionGap`, and the last one when the input ends. The segmenter itself never reads ahead; whether the whole
    /// pipeline does depends on `pages`. An on-demand producer such as `AsyncThrowingStream(unfolding:)` (what
    /// `PhotoLibraryRepository` returns) builds a page only when it is asked for; a buffering stream may run ahead.
    ///
    /// It runs in the consuming task: cancelling that task makes the next step throw `CancellationError`, also while
    /// waiting for a page. Errors from `pages` are rethrown.
    public func sessions(
        from pages: AsyncThrowingStream<[PhotoAsset], Error>,
        config: SessionConfig = .default
    ) -> SessionSequence {
        SessionSequence(pages: pages, config: config, logger: logger)
    }
}

/// What `SessionSegmenter` emits.
public enum SessionSegmentationEvent: Sendable, Hashable {
    /// A finished session. No later photo can join it.
    case session(PhotoSession)
    /// The input has ended; this is always the last event.
    case finished(SessionSegmentationSummary)
}

/// Counts for one segmentation run, for the scan summary and diagnostics.
public struct SessionSegmentationSummary: Sendable, Hashable {
    /// All sessions emitted.
    public var sessionCount = 0
    /// Sessions with a single photo. Each one saves a Vision request.
    public var singlePhotoSessionCount = 0
    /// Photos without a `creationDate`, left out of every session ("skipped (no date)").
    public var skippedNoDateCount = 0
    /// Runs that were larger than `maxSessionSize` and had to be split.
    public var oversizedSplitCount = 0

    /// Creates a summary.
    public init(
        sessionCount: Int = 0,
        singlePhotoSessionCount: Int = 0,
        skippedNoDateCount: Int = 0,
        oversizedSplitCount: Int = 0
    ) {
        self.sessionCount = sessionCount
        self.singlePhotoSessionCount = singlePhotoSessionCount
        self.skippedNoDateCount = skippedNoDateCount
        self.oversizedSplitCount = oversizedSplitCount
    }
}

/// The async sequence returned by `SessionSegmenter.sessions(from:config:)`.
public struct SessionSequence: AsyncSequence, Sendable {
    public typealias Element = SessionSegmentationEvent

    let pages: AsyncThrowingStream<[PhotoAsset], Error>
    let config: SessionConfig
    let logger: any SessionSegmentationLogging

    /// Creates an iterator. An `AsyncThrowingStream` can be iterated only once, so make one iterator per sequence.
    public func makeAsyncIterator() -> Iterator {
        Iterator(pages: pages.makeAsyncIterator(), accumulator: SessionAccumulator(config: config, logger: logger))
    }

    /// Pulls pages and emits sessions. Use it from one task only.
    public struct Iterator: AsyncIteratorProtocol {
        private var pages: AsyncThrowingStream<[PhotoAsset], Error>.Iterator
        private var accumulator: SessionAccumulator
        /// The page being read, and the index of its first photo not yet added to a run.
        private var page: [PhotoAsset] = []
        private var pageOffset = 0
        private var isInputFinished = false
        private var isDone = false

        /// Creates an iterator over `pages` that collects photos in `accumulator`.
        init(pages: AsyncThrowingStream<[PhotoAsset], Error>.Iterator, accumulator: SessionAccumulator) {
            self.pages = pages
            self.accumulator = accumulator
        }

        /// The next session, then the summary, then `nil`.
        ///
        /// Reads the current page only up to the next session boundary, and asks for the next page only when the
        /// current one is used up. Throws `CancellationError` if the task is cancelled; rethrows errors from the pages.
        public mutating func next() async throws -> SessionSegmentationEvent? {
            while !isDone {
                try Task.checkCancellation()
                if let session = accumulator.nextReadySession() {
                    return .session(session)
                }
                if pageOffset < page.count {
                    pageOffset = try accumulator.append(page, from: pageOffset)
                    continue
                }
                if isInputFinished {
                    isDone = true
                    return .finished(accumulator.finish())
                }
                page = []
                pageOffset = 0
                if let nextPage = try await pages.next() {
                    page = nextPage
                } else {
                    try accumulator.closeCurrentRun()
                    isInputFinished = true
                }
            }
            return nil
        }
    }
}

/// The synchronous core of the segmenter: collects photos into the current run and turns closed runs into sessions.
struct SessionAccumulator {
    private let config: SessionConfig
    private let logger: any SessionSegmentationLogging
    private var currentRun: [PhotoAsset] = []
    private var ready: [PhotoSession] = []
    private var readyIndex = 0
    private var summary = SessionSegmentationSummary()

    /// Creates an empty accumulator.
    init(config: SessionConfig, logger: any SessionSegmentationLogging) {
        self.config = config
        self.logger = logger
    }

    /// Adds photos of `page` (in `PhotoAsset.libraryOrder`) from index `start` on, and stops right after a photo
    /// that closes the current run, so that run's sessions can be emitted before the rest of the page is read.
    /// Returns the index of the first photo not yet added. Checks cancellation before every photo.
    mutating func append(_ page: [PhotoAsset], from start: Int) throws -> Int {
        var index = start
        while index < page.count {
            try Task.checkCancellation()
            let asset = page[index]
            index += 1
            guard let date = asset.creationDate else {
                summary.skippedNoDateCount += 1
                continue
            }
            if let previousDate = currentRun.last?.creationDate,
               previousDate.timeIntervalSince(date) > config.sessionGap {
                try closeCurrentRun()
                currentRun.append(asset)
                return index
            }
            currentRun.append(asset)
        }
        return index
    }

    /// Ends the current run, splitting it if it is too large, and queues its sessions.
    mutating func closeCurrentRun() throws {
        guard !currentRun.isEmpty else { return }
        let run = currentRun
        currentRun = []
        let parts = try Self.split(run, maxSize: config.maxSessionSize)
        if parts.count > 1 {
            summary.oversizedSplitCount += 1
            logger.didSplitOversizedSession(assetCount: run.count, partSizes: parts.map(\.count))
        }
        if readyIndex == ready.count {
            ready.removeAll(keepingCapacity: true)
            readyIndex = 0
        }
        for part in parts {
            guard let session = PhotoSession(assets: part) else { continue }
            ready.append(session)
            summary.sessionCount += 1
            if !session.needsAnalysis {
                summary.singlePhotoSessionCount += 1
            }
        }
    }

    /// The oldest queued session that hasn't been handed out yet.
    mutating func nextReadySession() -> PhotoSession? {
        guard readyIndex < ready.count else { return nil }
        defer { readyIndex += 1 }
        return ready[readyIndex]
    }

    /// The final counts. Reports them to the logger.
    func finish() -> SessionSegmentationSummary {
        logger.didFinish(summary)
        return summary
    }

    /// Splits a run (dated photos in `PhotoAsset.libraryOrder`) into parts of at most `maxSize`, keeping the order.
    ///
    /// An oversized part is cut at its largest gap between neighbours (the newest such gap on ties); a part without
    /// any gap is cut into chunks of `maxSize`. Each largest-gap lookup is O(log n) through `GapIndex`, so even a run
    /// whose gaps grow steadily (one photo split off per step) costs O(n log n), not O(n²). Uses an explicit stack,
    /// so a long run can't overflow the call stack.
    static func split(_ run: [PhotoAsset], maxSize: Int) throws -> [[PhotoAsset]] {
        guard run.count > maxSize else { return [run] }
        let gaps = GapIndex(run)
        var parts: [[PhotoAsset]] = []
        var pending: [Range<Int>] = [run.indices]
        while let part = pending.popLast() {
            try Task.checkCancellation()
            guard part.count > maxSize else {
                parts.append(Array(run[part]))
                continue
            }
            if let cut = gaps.largestGapCut(in: part) {
                // Older half first onto the stack, so the newer half is handled (and emitted) first.
                pending.append(cut..<part.upperBound)
                pending.append(part.lowerBound..<cut)
            } else {
                for start in stride(from: part.lowerBound, to: part.upperBound, by: maxSize) {
                    parts.append(Array(run[start..<min(start + maxSize, part.upperBound)]))
                }
            }
        }
        return parts
    }
}

/// Finds the largest gap between neighbouring photos in any part of a run in O(log n).
///
/// A segment tree over the gaps (`gaps[k]` is the time between photo `k` and photo `k + 1`, newest first). Each node
/// holds the index of the largest gap below it, the lowest index (the newest gap) on ties. Built in O(n).
struct GapIndex {
    private let gaps: [TimeInterval]
    private let leafCount: Int
    private let tree: [Int]

    /// Indexes the gaps of `run`, dated photos in `PhotoAsset.libraryOrder`.
    init(_ run: [PhotoAsset]) {
        let dates = run.map { $0.creationDate ?? .distantPast }
        let gaps = zip(dates, dates.dropFirst()).map { newer, older in newer.timeIntervalSince(older) }
        var leafCount = 1
        while leafCount < gaps.count {
            leafCount *= 2
        }
        var tree = Array(repeating: -1, count: 2 * leafCount)
        for index in gaps.indices {
            tree[leafCount + index] = index
        }
        for node in stride(from: leafCount - 1, through: 1, by: -1) {
            tree[node] = Self.better(tree[2 * node], tree[2 * node + 1], gaps: gaps)
        }
        self.gaps = gaps
        self.leafCount = leafCount
        self.tree = tree
    }

    /// For the photos `part` of the run, the index of the first photo after their largest positive gap, or `nil`
    /// if all their timestamps are equal.
    func largestGapCut(in part: Range<Int>) -> Int? {
        guard part.count >= 2 else { return nil }
        // The gaps between the photos of `part` are gaps[lowerBound ..< upperBound - 1].
        var low = part.lowerBound + leafCount
        var high = part.upperBound - 1 + leafCount
        var best = -1
        while low < high {
            if low % 2 == 1 {
                best = Self.better(best, tree[low], gaps: gaps)
                low += 1
            }
            if high % 2 == 1 {
                high -= 1
                best = Self.better(best, tree[high], gaps: gaps)
            }
            low /= 2
            high /= 2
        }
        guard best >= 0, gaps[best] > 0 else { return nil }
        return best + 1
    }

    /// The gap index with the larger gap; on equal gaps the lower (newer) index. `-1` means "none".
    private static func better(_ lhs: Int, _ rhs: Int, gaps: [TimeInterval]) -> Int {
        if lhs < 0 { return rhs }
        if rhs < 0 { return lhs }
        if gaps[lhs] != gaps[rhs] {
            return gaps[lhs] > gaps[rhs] ? lhs : rhs
        }
        return min(lhs, rhs)
    }
}
