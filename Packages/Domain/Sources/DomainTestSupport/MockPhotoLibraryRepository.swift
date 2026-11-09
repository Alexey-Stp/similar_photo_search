import Domain
import Foundation

/// In-memory `PhotoLibraryRepository` for tests.
///
/// Mirrors the PhotoKit repository's contract:
/// - applies the scope's album, date-range and screenshot filters to `assets`;
/// - when `includeBursts` is `false`, keeps one representative per `burstIdentifier`
///   (the first in `PhotoAsset.libraryOrder`; PhotoKit's own pick may differ);
/// - delivers assets in `PhotoAsset.libraryOrder`, in pages of `pageSize` that grow only to keep photos with the
///   same timestamp together; photos without a date start a new page;
/// - hands out pages on demand (`AsyncThrowingStream(unfolding:)`): a page is delivered only when the consumer asks
///   for it, so the stream never runs ahead of its consumer;
/// - `assetCount` counts a photo once per selected album it is in, like the real per-album sum.
public actor MockPhotoLibraryRepository: PhotoLibraryRepository {
    /// Every asset in the fake library.
    public private(set) var assets: [PhotoAsset]
    /// Album ID → IDs of the assets in that album.
    public private(set) var albumMembers: [String: Set<String>]
    /// Albums returned by `albums()`.
    public private(set) var albumSummaries: [AlbumSummary]
    /// If set, `assetPages` throws `error` instead of delivering page number `afterPages` (0-based).
    public private(set) var pageFailure: (afterPages: Int, error: any Error)?

    /// Number of `assetCount(scope:)` calls.
    public private(set) var assetCountCallCount = 0
    /// Number of streams returned by `assetPages(scope:pageSize:)` that started producing.
    public private(set) var assetPagesCallCount = 0
    /// Number of `albums()` calls.
    public private(set) var albumsCallCount = 0
    /// Scopes passed to `assetCount` and `assetPages`, in call order.
    public private(set) var requestedScopes: [ScanScope] = []

    /// Creates the mock.
    public init(
        assets: [PhotoAsset] = [],
        albumMembers: [String: Set<String>] = [:],
        albumSummaries: [AlbumSummary] = [],
        pageFailure: (afterPages: Int, error: any Error)? = nil
    ) {
        self.assets = assets
        self.albumMembers = albumMembers
        self.albumSummaries = albumSummaries
        self.pageFailure = pageFailure
    }

    /// Replaces the library contents, for example to simulate photos deleted outside the app.
    public func setAssets(_ newAssets: [PhotoAsset]) {
        assets = newAssets
    }

    /// Makes `assetPages` fail after delivering `afterPages` pages.
    public func setPageFailure(afterPages: Int, error: any Error) {
        pageFailure = (afterPages, error)
    }

    /// Whether the next `assetCount(scope:)` call should wait until `releaseHeldAssetCount()`.
    private var holdsNextAssetCount = false
    /// The suspended `assetCount(scope:)` call, if one is being held.
    private var heldAssetCount: CheckedContinuation<Void, Never>?

    /// Whether an `assetCount(scope:)` call is currently suspended by `holdNextAssetCount()`.
    public var isHoldingAssetCount: Bool {
        heldAssetCount != nil
    }

    /// Makes the next `assetCount(scope:)` call suspend until `releaseHeldAssetCount()`,
    /// so tests can control the order in which overlapping counts finish.
    public func holdNextAssetCount() {
        holdsNextAssetCount = true
    }

    /// Resumes the held `assetCount(scope:)` call, if any.
    public func releaseHeldAssetCount() {
        heldAssetCount?.resume()
        heldAssetCount = nil
    }

    /// Number of matching assets; with albums selected, the sum of each distinct album's matching assets.
    /// The count is taken when the call starts, then the call waits if a hold is set.
    public func assetCount(scope: ScanScope) async -> Int {
        assetCountCallCount += 1
        requestedScopes.append(scope)
        let count: Int
        if let albumIDs = scope.albumIDs {
            count = Set(albumIDs).reduce(0) { total, albumID in
                var singleAlbum = scope
                singleAlbum.albumIDs = [albumID]
                return total + matchingAssets(in: singleAlbum).count
            }
        } else {
            count = matchingAssets(in: scope).count
        }
        if holdsNextAssetCount {
            holdsNextAssetCount = false
            await withCheckedContinuation { heldAssetCount = $0 }
        }
        return count
    }

    /// Streams the matching assets, de-duplicated across albums, failing as configured by `pageFailure`.
    /// Pages are handed out one per request; cancelling the consuming task ends the stream with `CancellationError`.
    public nonisolated func assetPages(
        scope: ScanScope,
        pageSize: Int
    ) -> AsyncThrowingStream<[PhotoAsset], Error> {
        let cursor = MockPageCursor(repository: self, scope: scope, pageSize: pageSize)
        return AsyncThrowingStream(unfolding: { try await cursor.nextPage() })
    }

    /// Returns `albumSummaries`.
    public func albums() -> [AlbumSummary] {
        albumsCallCount += 1
        return albumSummaries
    }

    /// Records the request and splits the matching assets into pages.
    fileprivate func startPaging(
        scope: ScanScope,
        pageSize: Int
    ) -> (pages: [[PhotoAsset]], failure: (afterPages: Int, error: any Error)?) {
        assetPagesCallCount += 1
        requestedScopes.append(scope)
        return (Self.pages(of: matchingAssets(in: scope), pageSize: max(1, pageSize)), pageFailure)
    }

    /// Splits ordered assets into pages of `pageSize`, letting a page grow to keep equal timestamps together.
    /// The first undated asset always starts a new page.
    private static func pages(of ordered: [PhotoAsset], pageSize: Int) -> [[PhotoAsset]] {
        var pages: [[PhotoAsset]] = []
        var current: [PhotoAsset] = []
        for asset in ordered {
            if let last = current.last,
               startsNewPage(asset, after: last, currentCount: current.count, pageSize: pageSize) {
                pages.append(current)
                current = []
            }
            current.append(asset)
        }
        if !current.isEmpty {
            pages.append(current)
        }
        return pages
    }

    /// Whether `asset` must open a new page after `last`, given the current page's size.
    private static func startsNewPage(
        _ asset: PhotoAsset,
        after last: PhotoAsset,
        currentCount: Int,
        pageSize: Int
    ) -> Bool {
        if last.creationDate != nil, asset.creationDate == nil {
            return true
        }
        guard currentCount >= pageSize else { return false }
        return asset.creationDate == nil || asset.creationDate != last.creationDate
    }

    /// Assets in `scope`, de-duplicated, in `PhotoAsset.libraryOrder`.
    private func matchingAssets(in scope: ScanScope) -> [PhotoAsset] {
        let albumAssetIDs = scope.albumIDs.map { ids in
            ids.reduce(into: Set<String>()) { $0.formUnion(albumMembers[$1] ?? []) }
        }
        let ordered = assets
            .filter { asset in
                if let albumAssetIDs, !albumAssetIDs.contains(asset.id) {
                    return false
                }
                if scope.excludeScreenshots, asset.mediaSubtypes.contains(.screenshot) {
                    return false
                }
                if let range = scope.dateRange {
                    guard let date = asset.creationDate, range.contains(date) else { return false }
                }
                return true
            }
            .sorted(by: PhotoAsset.libraryOrder)
        guard !scope.includeBursts else { return ordered }
        var seenBursts: Set<String> = []
        return ordered.filter { asset in
            guard let burstID = asset.burstIdentifier else { return true }
            return seenBursts.insert(burstID).inserted
        }
    }
}

/// Hands out one stream's pages on request. Paging starts (and is counted) on the first request.
private actor MockPageCursor {
    private let repository: MockPhotoLibraryRepository
    private let scope: ScanScope
    private let pageSize: Int
    private var pages: [[PhotoAsset]]?
    private var failure: (afterPages: Int, error: any Error)?
    private var nextIndex = 0
    private var isFinished = false

    /// Creates a cursor for one `assetPages` call.
    init(repository: MockPhotoLibraryRepository, scope: ScanScope, pageSize: Int) {
        self.repository = repository
        self.scope = scope
        self.pageSize = pageSize
    }

    /// The next page, or `nil` at the end. Throws the injected failure in place of page `afterPages`
    /// (or at the end, if `afterPages` is past the last page), and `CancellationError` if the task is cancelled.
    func nextPage() async throws -> [PhotoAsset]? {
        guard !isFinished else { return nil }
        if Task.isCancelled {
            isFinished = true
            throw CancellationError()
        }
        if pages == nil {
            let started = await repository.startPaging(scope: scope, pageSize: pageSize)
            pages = started.pages
            failure = started.failure
        }
        let pages = pages ?? []
        if let failure,
           failure.afterPages == nextIndex || (nextIndex == pages.count && failure.afterPages > nextIndex) {
            isFinished = true
            throw failure.error
        }
        guard nextIndex < pages.count else {
            isFinished = true
            return nil
        }
        defer { nextIndex += 1 }
        return pages[nextIndex]
    }
}
