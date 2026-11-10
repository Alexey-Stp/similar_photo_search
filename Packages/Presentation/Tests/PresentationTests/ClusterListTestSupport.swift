import CoreGraphics
import Domain
import DomainTestSupport
import Foundation
import Presentation

/// `ThumbnailLoading` fake: streams end at once without an image; prefetch calls are recorded.
final class MockThumbnailLoader: ThumbnailLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var prefetchedIDs: [[String]] = []
    private var stoppedIDs: [[String]] = []
    private var stopAllCount = 0
    private var sizes: [CGSize] = []

    /// Every `prefetch` call's IDs, in order.
    var prefetched: [[String]] { locked { prefetchedIDs } }
    /// Every `stopPrefetching` call's IDs, in order.
    var stopped: [[String]] { locked { stoppedIDs } }
    /// Number of `stopAllPrefetching` calls.
    var stopAllCalls: Int { locked { stopAllCount } }
    /// Pixel sizes passed to `prefetch`.
    var prefetchSizes: [CGSize] { locked { sizes } }

    func thumbnail(for assetID: String, pixelSize: CGSize) -> AsyncStream<Thumbnail> {
        AsyncStream { $0.finish() }
    }

    func prefetch(_ assetIDs: [String], pixelSize: CGSize) async {
        locked {
            prefetchedIDs.append(assetIDs)
            sizes.append(pixelSize)
        }
    }

    func stopPrefetching(_ assetIDs: [String], pixelSize: CGSize) async {
        locked { stoppedIDs.append(assetIDs) }
    }

    func stopAllPrefetching() async {
        locked { stopAllCount += 1 }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Idle timer and background tasks that do nothing.
@MainActor
final class ListTestLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    func setIdleTimerDisabled(_ disabled: Bool) {}

    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        nil
    }

    func endBackgroundTask(_ token: BackgroundTaskToken) {}
}

/// A group list over mocks, with helpers to publish groups like a scan.
@MainActor
struct ClusterListHarness {
    let coordinator: MockScanCoordinator
    let library: MockPhotoLibraryRepository
    let sizes: MockAssetSizeEstimator
    let thumbnails: MockThumbnailLoader
    let changes: MockLibraryChangeObserver
    let lifecycle: ListTestLifecycle
    let scan: ScanViewModel
    let list: ClusterListViewModel

    /// - Parameters:
    ///   - photos: Photos that exist in the library (ID → creation time in seconds since 1970).
    ///   - sizes: File sizes by photo ID.
    init(photos: [String: TimeInterval] = [:], sizes: [String: Int64] = [:]) {
        let library = MockPhotoLibraryRepository(assets: photos.map { Self.asset($0.key, $0.value) })
        let estimator = MockAssetSizeEstimator(sizes: sizes)
        let coordinator = MockScanCoordinator()
        let thumbnails = MockThumbnailLoader()
        let changes = MockLibraryChangeObserver()
        let lifecycle = ListTestLifecycle()
        let scan = ScanViewModel(
            coordinator: coordinator,
            preferences: MockScopePreferencesStore(preferences: .default),
            selection: SelectionStore(sizes: estimator),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle
        )
        self.library = library
        self.sizes = estimator
        self.coordinator = coordinator
        self.thumbnails = thumbnails
        self.changes = changes
        self.lifecycle = lifecycle
        self.scan = scan
        list = ClusterListViewModel(
            scan: scan,
            library: library,
            sizes: estimator,
            thumbnails: thumbnails,
            libraryChanges: changes
        )
    }

    static func asset(_ id: String, _ seconds: TimeInterval) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: Date(timeIntervalSince1970: seconds),
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A group of `ids` that keeps the first and suggests deleting the others.
    static func group(_ ids: [String], needsReview: Bool = false, exact: Bool = false) -> ClusterSelection {
        ClusterSelection(
            cluster: SimilarityCluster(assetIDs: ids, suggestedKeeperID: ids.first, isExactDuplicate: exact),
            ranking: [],
            suggestedForDeletion: Set(ids.dropFirst()),
            needsReview: needsReview
        )
    }

    /// Publishes groups on the running scan and waits until the scan view model has them. Members not in the
    /// library yet are added to it (newest first), so they count as existing photos.
    func publish(_ groups: [ClusterSelection]) async {
        let current = await library.assets
        let known = Set(current.map(\.id))
        let members = groups.flatMap(\.cluster.assetIDs).filter { !known.contains($0) }
        let added = members.enumerated().map { Self.asset($1, 1_000_000 - TimeInterval($0)) }
        await library.setAssets(current + added)
        let before = scan.clusterRevision
        await coordinator.send(.added(groups))
        _ = await eventually { scan.clusterRevision > before }
        list.clustersChanged()
        await list.waitForLoads()
    }

    /// Removes groups on the running scan and waits until the scan view model applied it.
    func remove(_ ids: [String]) async {
        let before = scan.clusterRevision
        await coordinator.send(.removed(ids))
        _ = await eventually { scan.clusterRevision > before }
        list.clustersChanged()
        await list.waitForLoads()
    }

    /// Polls on the main actor until `condition` holds (up to 2 s).
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }
}
