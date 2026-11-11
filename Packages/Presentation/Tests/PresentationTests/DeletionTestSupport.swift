import Domain
import DomainTestSupport
import Foundation
import Presentation

/// `AssetDeletionService` that holds every call until `release(with:)`, like a system alert nobody answered yet.
actor GatedDeletionService: AssetDeletionService {
    private var waiting: [CheckedContinuation<DeletionResult, Never>] = []
    /// Asset IDs of each call, in order.
    private(set) var requests: [[String]] = []

    /// Records the call and waits for `release(with:)`.
    func delete(assetIDs: [String]) async -> DeletionResult {
        requests.append(assetIDs)
        return await withCheckedContinuation { waiting.append($0) }
    }

    /// Answers every waiting call with `result`.
    func release(with result: DeletionResult) {
        let continuations = waiting
        waiting = []
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }

    /// Number of calls waiting for an answer.
    var waitingCount: Int { waiting.count }
}

/// Background tasks that are granted and recorded; the idle timer does nothing.
@MainActor
final class RecordingLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    private var next = 0
    /// Names of the tasks begun, in order.
    private(set) var begun: [String] = []
    /// Tokens ended, in order.
    private(set) var ended: [BackgroundTaskToken] = []

    /// Does nothing.
    func setIdleTimerDisabled(_ disabled: Bool) {}

    /// Grants a task and records its name.
    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        next += 1
        begun.append(name)
        return BackgroundTaskToken(rawValue: next)
    }

    /// Records the token.
    func endBackgroundTask(_ token: BackgroundTaskToken) {
        ended.append(token)
    }
}

/// `PhotosAppOpening` spy.
@MainActor
final class PhotosAppOpenerSpy: PhotosAppOpening {
    var canOpenPhotos = true
    private(set) var openCount = 0

    /// Counts the call.
    func openPhotos() {
        openCount += 1
    }
}

/// A clock the test moves by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

/// A scan with groups in its store, and a deletion flow over mocks.
@MainActor
struct DeletionHarness {
    let coordinator = MockScanCoordinator()
    let cache = MockFeaturePrintCache()
    let lifecycle = RecordingLifecycle()
    let photosApp = PhotosAppOpenerSpy()
    let clock = TestClock()
    let scan: ScanViewModel

    /// - Parameter sizes: File sizes by photo ID.
    init(sizes: [String: Int64] = [:]) {
        let clock = clock
        scan = ScanViewModel(
            coordinator: coordinator,
            preferences: MockScopePreferencesStore(preferences: .default),
            selection: SelectionStore(sizes: MockAssetSizeEstimator(sizes: sizes)),
            idleTimer: lifecycle,
            backgroundTasks: lifecycle,
            now: { clock.now }
        )
    }

    /// The selection store of the scan.
    var store: SelectionStore { scan.selection }

    /// Shows groups that keep their first photo and suggest deleting the others.
    func show(_ groups: [[String]]) {
        scan.showStoredResults(groups.map { ClusterListHarness.group($0) })
    }

    /// A flow for the store's selected photos over `deletion`.
    func makeFlow(_ deletion: any AssetDeletionService) -> DeletionViewModel {
        DeletionViewModel(
            assetIDs: store.selectedAssetIDs,
            deletion: deletion,
            cache: cache,
            scan: scan,
            thumbnails: MockThumbnailLoader(),
            photosApp: photosApp,
            backgroundTasks: lifecycle
        )
    }
}
