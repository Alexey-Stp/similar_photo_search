@testable import DataLayer
import Domain
import Foundation
import Testing

/// Thread-safe record of the ranges a source has read, shareable with the producer actor.
private final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Range<Int>] = []

    /// The ranges read so far, in order.
    var ranges: [Range<Int>] {
        lock.withLock { storage }
    }

    /// Records one read.
    func append(_ range: Range<Int>) {
        lock.withLock { storage.append(range) }
    }
}

/// In-memory `AssetSource` that records which ranges were read.
private final class ArraySource: AssetSource {
    let items: [PhotoAsset]
    let log: ReadLog
    private let onRead: ((Range<Int>) -> Void)?

    init(_ items: [PhotoAsset], log: ReadLog = ReadLog(), onRead: ((Range<Int>) -> Void)? = nil) {
        self.items = items
        self.log = log
        self.onRead = onRead
    }

    var readRanges: [Range<Int>] {
        log.ranges
    }

    var count: Int {
        items.count
    }

    func assets(in range: Range<Int>) -> [PhotoAsset] {
        log.append(range)
        onRead?(range)
        return Array(items[range])
    }
}

private func asset(_ id: String, _ seconds: TimeInterval?) -> PhotoAsset {
    PhotoAsset(
        id: id,
        creationDate: seconds.map { Date(timeIntervalSince1970: $0) },
        pixelWidth: 1,
        pixelHeight: 1,
        isFavorite: false,
        mediaSubtypes: []
    )
}

private func drain(_ pager: inout OrderedAssetPager) throws -> [[String]] {
    var pages: [[String]] = []
    while let page = try pager.nextPage() {
        pages.append(page.map(\.id))
    }
    return pages
}

struct OrderedAssetPagerTests {
    @Test func noSourcesOrEmptySourcesYieldNothing() throws {
        var noSources = OrderedAssetPager(sources: [], pageSize: 10)
        let noSourcesPage = try noSources.nextPage()
        #expect(noSourcesPage == nil)
        var empty = OrderedAssetPager(sources: [ArraySource([])], pageSize: 10)
        let firstPage = try empty.nextPage()
        let secondPage = try empty.nextPage()
        #expect(firstPage == nil)
        #expect(secondPage == nil)
    }

    @Test func splitsIntoPagesOfPageSize() throws {
        let source = ArraySource([asset("a", 5), asset("b", 4), asset("c", 3), asset("d", 2), asset("e", 1)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        let pages = try drain(&pager)
        #expect(pages == [["a", "b"], ["c", "d"], ["e"]])
    }

    @Test func pageSizeBelowOneIsTreatedAsOne() throws {
        var pager = OrderedAssetPager(sources: [ArraySource([asset("a", 2), asset("b", 1)])], pageSize: 0)
        let pages = try drain(&pager)
        #expect(pages == [["a"], ["b"]])
    }

    @Test func equalTimestampsAcrossAPageBoundaryStayTogetherSortedByID() throws {
        // PhotoKit returns ties in an unspecified order.
        let source = ArraySource([
            asset("new", 5), asset("t-c", 4), asset("t-a", 4), asset("t-b", 4), asset("old", 3)
        ])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        let pages = try drain(&pager)
        #expect(pages == [["new", "t-a", "t-b", "t-c"], ["old"]])
    }

    @Test func assetsWithoutDateComeLastSortedByID() throws {
        let source = ArraySource([asset("n-z", nil), asset("d1", 10), asset("n-y", nil), asset("d2", 5)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        let pages = try drain(&pager)
        #expect(pages == [["d1", "d2"], ["n-y", "n-z"]])
    }

    @Test func mergesSeveralSourcesByDateAndDeliversSharedAssetsOnce() throws {
        let albumA = ArraySource([asset("a10", 10), asset("shared", 7), asset("a3", 3), asset("undated", nil)])
        let albumB = ArraySource([asset("b9", 9), asset("shared", 7), asset("b1", 1), asset("undated", nil)])
        var pager = OrderedAssetPager(sources: [albumA, albumB], pageSize: 10)
        let pages = try drain(&pager)
        #expect(pages == [["a10", "b9", "shared", "a3", "b1"], ["undated"]])
    }

    @Test func readsSourcesLazilyInChunks() throws {
        let source = ArraySource([asset("a", 5), asset("b", 4), asset("c", 3), asset("d", 2), asset("e", 1)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        _ = try pager.nextPage()
        // The first page needs one look past its end to rule out a tie, so two chunks are read.
        #expect(source.readRanges == [0..<2, 2..<4])
        _ = try drain(&pager)
        #expect(source.readRanges == [0..<2, 2..<4, 4..<5])
    }

    @Test func streamDeliversAllPagesThenFinishes() async throws {
        let items = [asset("a", 3), asset("b", 2), asset("c", 1)]
        let stream = AssetPageProducer.stream(pageSize: 2) { [ArraySource(items)] }
        var pages: [[String]] = []
        for try await page in stream {
            pages.append(page.map(\.id))
        }
        #expect(pages == [["a", "b"], ["c"]])
    }

    @Test func cancellationInsideALongTimestampRunStopsReadingAndThrows() async {
        // 20 photos with one timestamp: without cancellation checks the whole run would be read for one page.
        let items = (0..<20).map { asset(String(format: "id%02d", $0), 100) }
        let outcome = await Task {
            let source = ArraySource(items) { range in
                if range.lowerBound == 4 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            var pager = OrderedAssetPager(sources: [source], pageSize: 2)
            do {
                _ = try pager.nextPage()
                return (threw: false, reads: source.readRanges)
            } catch {
                return (threw: error is CancellationError, reads: source.readRanges)
            }
        }.value
        #expect(outcome.threw)
        #expect(outcome.reads == [0..<2, 2..<4, 4..<6])
    }

    @Test func cancellingTheConsumerStopsTheStream() async {
        let items = (0..<10).map { asset("id\($0)", TimeInterval(100 - $0)) }
        let log = ReadLog()
        let stream = AssetPageProducer.stream(pageSize: 1) { [ArraySource(items, log: log)] }
        let consumer = Task {
            var received = 0
            var readsAtFirstPage: [Range<Int>] = []
            do {
                for try await _ in stream {
                    received += 1
                    readsAtFirstPage = log.ranges
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            } catch {
                #expect(error is CancellationError)
            }
            return (received: received, readsAtFirstPage: readsAtFirstPage)
        }
        // Awaiting the consumer also awaits the producer: the unfolding stream calls it from the consumer's `next()`.
        let result = await consumer.value
        #expect(result.received == 1)
        // The first page reads one chunk plus one chunk of lookahead (to rule out a timestamp tie), nothing more.
        #expect(result.readsAtFirstPage == [0..<1, 1..<2])
        #expect(log.ranges == [0..<1, 1..<2])
    }
}
