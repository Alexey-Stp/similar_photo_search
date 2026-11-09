import Foundation

/// Cuts the date-ordered photo stream from `PhotoLibraryRepository.assetPages` into shooting sessions.
///
/// Rules:
/// - Two neighbouring photos are in the same session when their `creationDate`s are at most `sessionGap` apart.
///   Only the gap counts: not the calendar day, and not `burstIdentifier`.
/// - A run larger than `maxSessionSize` is split at its largest internal gap, again and again, until every part
///   fits.
///   A part with no gap left (all timestamps equal) is cut into chunks of `maxSessionSize` in `PhotoAsset.libraryOrder`.
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
    /// The sequence pulls a page only when the consumer asks for an event it can't produce yet, so it never reads
    /// ahead: a session is emitted as soon as a later photo shows a gap larger than `sessionGap`, and the last one
    /// when the input ends. It runs in the consuming task: cancelling that task makes the next step throw
    /// `CancellationError`. Errors from `pages` are rethrown.
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

    public func makeAsyncIterator() -> Iterator {
        Iterator(pages: pages.makeAsyncIterator(), accumulator: SessionAccumulator(config: config, logger: logger))
    }

    /// Pulls pages and emits sessions. Use it from one task only.
    public struct Iterator: AsyncIteratorProtocol {
        private var pages: AsyncThrowingStream<[PhotoAsset], Error>.Iterator
        private var accumulator: SessionAccumulator
        private var isInputFinished = false
        private var isDone = false

        init(pages: AsyncThrowingStream<[PhotoAsset], Error>.Iterator, accumulator: SessionAccumulator) {
            self.pages = pages
            self.accumulator = accumulator
        }

        public mutating func next() async throws -> SessionSegmentationEvent? {
            while !isDone {
                try Task.checkCancellation()
                if let session = accumulator.nextReadySession() {
                    return .session(session)
                }
                if isInputFinished {
                    isDone = true
                    return .finished(accumulator.finish())
                }
                if let page = try await pages.next() {
                    try accumulator.append(page)
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

    init(config: SessionConfig, logger: any SessionSegmentationLogging) {
        self.config = config
        self.logger = logger
    }

    /// Adds a page of photos in `PhotoAsset.libraryOrder`. Checks cancellation before every photo.
    mutating func append(_ page: [PhotoAsset]) throws {
        for asset in page {
            try Task.checkCancellation()
            guard let date = asset.creationDate else {
                summary.skippedNoDateCount += 1
                continue
            }
            if let previousDate = currentRun.last?.creationDate,
               previousDate.timeIntervalSince(date) > config.sessionGap {
                try closeCurrentRun()
            }
            currentRun.append(asset)
        }
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
    /// any gap is cut into chunks of `maxSize`. Uses an explicit stack, so a long run can't overflow the call stack.
    static func split(_ run: [PhotoAsset], maxSize: Int) throws -> [[PhotoAsset]] {
        guard run.count > maxSize else { return [run] }
        var parts: [[PhotoAsset]] = []
        var pending: [ArraySlice<PhotoAsset>] = [run[...]]
        while let part = pending.popLast() {
            try Task.checkCancellation()
            guard part.count > maxSize else {
                parts.append(Array(part))
                continue
            }
            if let cut = largestGapIndex(in: part) {
                // Older half first onto the stack, so the newer half is handled (and emitted) first.
                pending.append(part[cut...])
                pending.append(part[..<cut])
            } else {
                for start in stride(from: part.startIndex, to: part.endIndex, by: maxSize) {
                    parts.append(Array(part[start..<min(start + maxSize, part.endIndex)]))
                }
            }
        }
        return parts
    }

    /// The index of the first photo after the largest positive gap in `part`, or `nil` if all timestamps are equal.
    private static func largestGapIndex(in part: ArraySlice<PhotoAsset>) -> Int? {
        var best: (index: Int, gap: TimeInterval)?
        for index in part.indices.dropFirst() {
            guard let newer = part[index - 1].creationDate, let older = part[index].creationDate else { continue }
            let gap = newer.timeIntervalSince(older)
            if gap > (best?.gap ?? 0) {
                best = (index, gap)
            }
        }
        return best?.index
    }
}
