import Domain
import Foundation

/// Turns one or more `creationDate`-sorted `AssetSource`s into pages in `PhotoAsset.libraryOrder`.
///
/// - Several sources (several selected albums) are merged by date; an asset in more than one is delivered once.
/// - PhotoKit cannot sort by `localIdentifier`, so the run of assets that share the last timestamp of a page is
///   held back until a later asset has a different timestamp, and each page is then sorted by
///   `PhotoAsset.libraryOrder`. A page therefore has at least `pageSize` assets (except the last one) and
///   grows past it only by such a run.
/// - Assets without a `creationDate` are collected as they are met and delivered after all dated assets,
///   sorted by `id`. Only these are held until the end; the library usually has few of them.
/// - Sources are read in chunks of `pageSize`, never all at once.
struct OrderedAssetPager {
    private var cursors: [SourceCursor]
    private let pageSize: Int
    /// Only needed when sources can overlap.
    private let deduplicates: Bool
    private var deliveredIDs: Set<String> = []
    private var pending: [PhotoAsset] = []
    private var undated: [PhotoAsset] = []
    private var undatedOffset = 0
    private var isDatedPhaseFinished = false

    /// Creates a pager. `pageSize` values below 1 are treated as 1.
    init(sources: [any AssetSource], pageSize: Int) {
        let size = max(1, pageSize)
        self.pageSize = size
        self.cursors = sources.map { SourceCursor(source: $0, chunkSize: size) }
        self.deduplicates = sources.count > 1
    }

    /// The next page, or `nil` when every asset has been delivered.
    mutating func nextPage() -> [PhotoAsset]? {
        if !isDatedPhaseFinished {
            if let page = nextDatedPage() {
                return page
            }
            isDatedPhaseFinished = true
            undated.sort(by: PhotoAsset.libraryOrder)
        }
        return nextUndatedPage()
    }

    private mutating func nextDatedPage() -> [PhotoAsset]? {
        while let asset = nextDatedAsset() {
            if pending.count >= pageSize, asset.creationDate != pending.last?.creationDate {
                let page = pending.sorted(by: PhotoAsset.libraryOrder)
                pending = [asset]
                return page
            }
            pending.append(asset)
        }
        guard !pending.isEmpty else { return nil }
        let page = pending.sorted(by: PhotoAsset.libraryOrder)
        pending = []
        return page
    }

    private mutating func nextUndatedPage() -> [PhotoAsset]? {
        guard undatedOffset < undated.count else { return nil }
        let end = min(undatedOffset + pageSize, undated.count)
        let page = Array(undated[undatedOffset..<end])
        undatedOffset = end
        return page
    }

    /// The newest not-yet-delivered dated asset across all sources. Undated assets met on the way are set aside.
    private mutating func nextDatedAsset() -> PhotoAsset? {
        while let index = indexOfNewestHead() {
            let asset = cursors[index].pop()
            if markDelivered(asset) {
                return asset
            }
        }
        return nil
    }

    /// The source whose next dated asset is the newest; ties go to the first source.
    private mutating func indexOfNewestHead() -> Int? {
        var newest: (index: Int, date: Date)?
        for index in cursors.indices {
            guard let date = datedHeadDate(at: index) else { continue }
            if newest.map({ date > $0.date }) ?? true {
                newest = (index, date)
            }
        }
        return newest?.index
    }

    /// The date of the source's next asset, after moving any undated assets in front of it aside.
    private mutating func datedHeadDate(at index: Int) -> Date? {
        while let head = cursors[index].peek() {
            if let date = head.creationDate {
                return date
            }
            let asset = cursors[index].pop()
            if markDelivered(asset) {
                undated.append(asset)
            }
        }
        return nil
    }

    /// Records the asset as delivered. Returns `false` if it already was (it is in an earlier source too).
    private mutating func markDelivered(_ asset: PhotoAsset) -> Bool {
        guard deduplicates else { return true }
        return deliveredIDs.insert(asset.id).inserted
    }
}

/// Reads one source front to back in chunks.
private struct SourceCursor {
    private let source: any AssetSource
    private let count: Int
    private let chunkSize: Int
    private var buffer: [PhotoAsset] = []
    private var bufferIndex = 0
    private var nextOffset = 0

    init(source: any AssetSource, chunkSize: Int) {
        self.source = source
        self.count = source.count
        self.chunkSize = chunkSize
    }

    /// The next asset without consuming it, or `nil` at the end.
    mutating func peek() -> PhotoAsset? {
        if bufferIndex == buffer.count {
            guard nextOffset < count else { return nil }
            let end = min(nextOffset + chunkSize, count)
            buffer = source.assets(in: nextOffset..<end)
            bufferIndex = 0
            nextOffset = end
            guard !buffer.isEmpty else { return nil }
        }
        return buffer[bufferIndex]
    }

    /// Consumes the asset returned by the last `peek()`. Call only after `peek()` returned an asset.
    mutating func pop() -> PhotoAsset {
        let asset = buffer[bufferIndex]
        bufferIndex += 1
        return asset
    }
}

/// Produces pages on demand for `AsyncThrowingStream(unfolding:)`, so the stream never runs ahead of its consumer.
///
/// The sources are created on the first request, inside this actor, so no PhotoKit object leaves it.
actor AssetPageProducer {
    private let pageSize: Int
    private let makeSources: @Sendable () -> [any AssetSource]
    private var pager: OrderedAssetPager?

    init(pageSize: Int, makeSources: @escaping @Sendable () -> [any AssetSource]) {
        self.pageSize = pageSize
        self.makeSources = makeSources
    }

    /// The next page, or `nil` at the end. Throws `CancellationError` if the consuming task was cancelled.
    func nextPage() throws -> [PhotoAsset]? {
        try Task.checkCancellation()
        if pager == nil {
            pager = OrderedAssetPager(sources: makeSources(), pageSize: pageSize)
        }
        return pager?.nextPage()
    }

    /// A stream of pages that pulls one page each time the consumer asks for the next element.
    static func stream(
        pageSize: Int,
        makeSources: @escaping @Sendable () -> [any AssetSource]
    ) -> AsyncThrowingStream<[PhotoAsset], Error> {
        let producer = AssetPageProducer(pageSize: pageSize, makeSources: makeSources)
        return AsyncThrowingStream(unfolding: { try await producer.nextPage() })
    }
}
