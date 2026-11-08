import Domain
import Foundation

/// In-memory `PhotoLibraryRepository` for tests.
///
/// Applies the scope's album, date-range and screenshot filters to `assets`, delivers them in
/// `PhotoAsset.libraryOrder` and splits them into pages of exactly `pageSize`.
/// Bursts are not modelled: every asset is returned whatever `includeBursts` says.
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

    public func assetCount(scope: ScanScope) -> Int {
        assetCountCallCount += 1
        requestedScopes.append(scope)
        return matchingAssets(in: scope).count
    }

    public nonisolated func assetPages(
        scope: ScanScope,
        pageSize: Int
    ) -> AsyncThrowingStream<[PhotoAsset], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let (pages, failure) = await self.startPaging(scope: scope, pageSize: pageSize)
                for (index, page) in pages.enumerated() {
                    if let failure, failure.afterPages == index {
                        continuation.finish(throwing: failure.error)
                        return
                    }
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(page)
                }
                if let failure, failure.afterPages >= pages.count {
                    continuation.finish(throwing: failure.error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func albums() -> [AlbumSummary] {
        albumsCallCount += 1
        return albumSummaries
    }

    private func startPaging(
        scope: ScanScope,
        pageSize: Int
    ) -> (pages: [[PhotoAsset]], failure: (afterPages: Int, error: any Error)?) {
        assetPagesCallCount += 1
        requestedScopes.append(scope)
        let ordered = matchingAssets(in: scope)
        let size = max(1, pageSize)
        let pages = stride(from: 0, to: ordered.count, by: size).map {
            Array(ordered[$0..<min($0 + size, ordered.count)])
        }
        return (pages, pageFailure)
    }

    private func matchingAssets(in scope: ScanScope) -> [PhotoAsset] {
        let albumAssetIDs = scope.albumIDs.map { ids in
            ids.reduce(into: Set<String>()) { $0.formUnion(albumMembers[$1] ?? []) }
        }
        return assets
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
    }
}
