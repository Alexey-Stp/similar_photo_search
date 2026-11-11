import Domain
import Foundation
import Observation

/// The deletion flow of one "Delete N photos" tap: review → deleting → result.
///
/// - **Review** shows what will be deleted. Nothing is deleted before `confirm()`.
/// - **Deleting** lasts until the system alert is answered; the sheet can't be dismissed meanwhile. A background task
///   keeps the app running long enough to finish the bookkeeping if the user leaves the app right after answering.
/// - A **user cancel** returns to the review with the selection untouched (only photos an earlier chunk already
///   deleted are processed).
/// - After any result, only the photos actually deleted are purged from the cache, removed from the groups and
///   excluded from the running scan (`ScanViewModel.deletionFinished(deleted:)`); no rescan.
///
/// Built per presentation by `ViewModelFactory.makeDeletionViewModel(request:)`.
@Observable
@MainActor
public final class DeletionViewModel {
    /// Where the flow is.
    public enum State: Sendable, Hashable {
        /// The review sheet: count, size, groups, thumbnails, Recently Deleted note.
        case review
        /// Waiting for the system alert and the deletion.
        case deleting
        /// Everything was deleted.
        case success(DeletionOutcome)
        /// Some photos were not deleted.
        case partial(DeletionOutcome)
        /// Nothing could be deleted; the message says why.
        case failed(String)
    }

    /// Where the flow is.
    public private(set) var state: State = .review
    /// The photos the review shows and `confirm()` deletes, in list order.
    public private(set) var assetIDs: [String]

    /// Thumbnails for the review strip and the failed photos.
    @ObservationIgnored public let thumbnails: any ThumbnailLoading
    @ObservationIgnored private let deletion: any AssetDeletionService
    @ObservationIgnored private let cache: any FeaturePrintCache
    @ObservationIgnored private let scan: ScanViewModel
    @ObservationIgnored private let photosApp: any PhotosAppOpening
    @ObservationIgnored private let backgroundTasks: any BackgroundTaskRunning

    /// Creates the flow for the photos selected when the delete button was tapped.
    /// - Parameters:
    ///   - assetIDs: The photos to delete, in list order.
    ///   - scan: The scan of this app session; its selection store holds the groups.
    ///   - cache: Feature-print cache; deleted photos are purged from it.
    public init(
        assetIDs: [String],
        deletion: any AssetDeletionService,
        cache: any FeaturePrintCache,
        scan: ScanViewModel,
        thumbnails: any ThumbnailLoading,
        photosApp: any PhotosAppOpening,
        backgroundTasks: any BackgroundTaskRunning
    ) {
        var seen = Set<String>()
        self.assetIDs = assetIDs.filter { seen.insert($0).inserted }
        self.deletion = deletion
        self.cache = cache
        self.scan = scan
        self.thumbnails = thumbnails
        self.photosApp = photosApp
        self.backgroundTasks = backgroundTasks
    }

    // MARK: - Review

    /// Count and estimated size: "38 photos, about 214 MB will be deleted".
    public var summary: DeletionSummary {
        // Read the store's summary first, so the review updates when sizes arrive.
        _ = scan.selection.summary
        return scan.selection.summary(of: assetIDs)
    }

    /// Number of groups the photos come from.
    public var groupCount: Int {
        Set(assetIDs.compactMap { scan.selection.clusterID(containing: $0) }).count
    }

    /// Whether the sheet must stay up (while the system alert and the deletion run).
    public var isDismissDisabled: Bool { state == .deleting }

    /// Whether the result offers "Open Photos".
    public var canOpenPhotos: Bool { photosApp.canOpenPhotos }

    // MARK: - Actions

    /// The user confirmed the review: asks the system to delete the photos and shows the result.
    public func confirm() async {
        guard state == .review, !assetIDs.isEmpty else { return }
        state = .deleting
        let requested = assetIDs
        let token = backgroundTasks.beginBackgroundTask(named: "SimilarPhotos.delete") { [weak self] in
            self?.endBackgroundTask()
        }
        backgroundTask = token
        scan.deletionStarted()

        let result = await deletion.delete(assetIDs: requested)

        let freed = scan.selection.summary(of: requested.filter(result.deleted.contains))
        await scan.deletionFinished(deleted: result.deleted)
        if !result.deleted.isEmpty {
            // A failed purge only leaves stale rows; the change tracker evicts them on the next scan (SPS-10).
            try? await cache.purge(assetIDs: requested.filter(result.deleted.contains))
        }
        state = nextState(after: result, requested: requested, freed: freed)
        endBackgroundTask()
    }

    /// "Open Photos" on the result screen.
    public func openPhotos() {
        photosApp.openPhotos()
    }

    // MARK: - Private

    @ObservationIgnored private var backgroundTask: BackgroundTaskToken?

    private func endBackgroundTask() {
        guard let token = backgroundTask else { return }
        backgroundTask = nil
        backgroundTasks.endBackgroundTask(token)
    }

    /// Review again after a cancel, the error for lost access, else success or a partial result.
    private func nextState(after result: DeletionResult, requested: [String], freed: DeletionSummary) -> State {
        let remaining = requested.filter { !result.deleted.contains($0) }
        if result.cancelled {
            assetIDs = remaining
            if !remaining.isEmpty || result.deleted.isEmpty {
                return .review
            }
        }
        if result.isPermissionDenied, result.deleted.isEmpty {
            return .failed(String(localized: "deletion.error.permission", bundle: .module))
        }
        let outcome = DeletionOutcome(
            requestedCount: requested.count,
            deletedCount: result.deleted.count,
            freed: freed,
            failures: remaining.map { DeletionOutcome.Failure(id: $0, reason: result.failed[$0] ?? .notDeleted) }
        )
        return remaining.isEmpty ? .success(outcome) : .partial(outcome)
    }
}
