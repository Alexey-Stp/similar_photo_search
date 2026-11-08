@testable import DataLayer
import Domain
import Foundation
import Testing

/// In-memory `AssetSource` that records which ranges were read.
private final class ArraySource: AssetSource {
    let items: [PhotoAsset]
    private(set) var readRanges: [Range<Int>] = []

    init(_ items: [PhotoAsset]) {
        self.items = items
    }

    var count: Int {
        items.count
    }

    func assets(in range: Range<Int>) -> [PhotoAsset] {
        readRanges.append(range)
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

private func drain(_ pager: inout OrderedAssetPager) -> [[String]] {
    var pages: [[String]] = []
    while let page = pager.nextPage() {
        pages.append(page.map(\.id))
    }
    return pages
}

struct OrderedAssetPagerTests {
    @Test func noSourcesOrEmptySourcesYieldNothing() {
        var noSources = OrderedAssetPager(sources: [], pageSize: 10)
        #expect(noSources.nextPage() == nil)
        var empty = OrderedAssetPager(sources: [ArraySource([])], pageSize: 10)
        #expect(empty.nextPage() == nil)
        #expect(empty.nextPage() == nil)
    }

    @Test func splitsIntoPagesOfPageSize() {
        let source = ArraySource([asset("a", 5), asset("b", 4), asset("c", 3), asset("d", 2), asset("e", 1)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        #expect(drain(&pager) == [["a", "b"], ["c", "d"], ["e"]])
    }

    @Test func pageSizeBelowOneIsTreatedAsOne() {
        var pager = OrderedAssetPager(sources: [ArraySource([asset("a", 2), asset("b", 1)])], pageSize: 0)
        #expect(drain(&pager) == [["a"], ["b"]])
    }

    @Test func equalTimestampsAcrossAPageBoundaryStayTogetherSortedByID() {
        // PhotoKit returns ties in an unspecified order.
        let source = ArraySource([
            asset("new", 5), asset("t-c", 4), asset("t-a", 4), asset("t-b", 4), asset("old", 3)
        ])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        #expect(drain(&pager) == [["new", "t-a", "t-b", "t-c"], ["old"]])
    }

    @Test func assetsWithoutDateComeLastSortedByID() {
        let source = ArraySource([asset("n-z", nil), asset("d1", 10), asset("n-y", nil), asset("d2", 5)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        #expect(drain(&pager) == [["d1", "d2"], ["n-y", "n-z"]])
    }

    @Test func mergesSeveralSourcesByDateAndDeliversSharedAssetsOnce() {
        let albumA = ArraySource([asset("a10", 10), asset("shared", 7), asset("a3", 3), asset("undated", nil)])
        let albumB = ArraySource([asset("b9", 9), asset("shared", 7), asset("b1", 1), asset("undated", nil)])
        var pager = OrderedAssetPager(sources: [albumA, albumB], pageSize: 10)
        #expect(drain(&pager) == [["a10", "b9", "shared", "a3", "b1"], ["undated"]])
    }

    @Test func readsSourcesLazilyInChunks() {
        let source = ArraySource([asset("a", 5), asset("b", 4), asset("c", 3), asset("d", 2), asset("e", 1)])
        var pager = OrderedAssetPager(sources: [source], pageSize: 2)
        _ = pager.nextPage()
        // The first page needs one look past its end to rule out a tie, so two chunks are read.
        #expect(source.readRanges == [0..<2, 2..<4])
        _ = drain(&pager)
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

    @Test func cancellingTheConsumerStopsTheStream() async {
        let items = (0..<10).map { asset("id\($0)", TimeInterval(100 - $0)) }
        let stream = AssetPageProducer.stream(pageSize: 1) { [ArraySource(items)] }
        let consumer = Task {
            var received = 0
            do {
                for try await _ in stream {
                    received += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            } catch {
                #expect(error is CancellationError)
            }
            return received
        }
        #expect(await consumer.value == 1)
    }
}
