import CoreGraphics
import Domain
import Foundation
import Observation

/// Drives the group list: which rows to show (filter, sort, live updates), the per-photo dates and availability,
/// the per-group reclaimable size, the thumbnail prefetch window and the selection actions.
///
/// - **Date sort** shows `ScanViewModel.rowOrder`: new groups are appended, groups newer than every row go on top
///   (the screen anchors the scroll position, so nothing visible moves).
/// - **Size sort** is a frozen order, recomputed only while the user is not touching the list. Groups that arrive
///   while they scroll appear at their sorted position when scrolling ends.
/// - Cards read their selection through `SelectionStore.state(for:)`, so a toggle re-renders one card.
///
/// One instance per app session (`ViewModelFactory.clusterListViewModel`), so filter and sort survive navigation.
@Observable
@MainActor
public final class ClusterListViewModel {
    /// Which groups the list shows.
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        /// Every group.
        case all
        /// Groups flagged "Review recommended".
        case needsReview
        /// Groups whose photos are copies of the same image.
        case exactDuplicates

        public var id: Self { self }
    }

    /// How the groups are ordered.
    public enum Sort: String, CaseIterable, Identifiable, Sendable {
        /// Newest first, in the order the scan published them.
        case date
        /// Largest reclaimable size first.
        case reclaimableSize

        public var id: Self { self }
    }

    /// What the user asked to delete with the bottom bar's delete button; SPS-25 presents the review sheet for it.
    public struct DeletionRequest: Identifiable, Hashable, Sendable {
        /// Identifies one tap.
        public let id = UUID()
        /// The photos selected when the button was tapped, in list order.
        public let assetIDs: [String]
    }

    /// Thumbnails are this many points wide and high.
    public static let thumbnailSide: CGFloat = 88
    /// How many rows above and below the last row that appeared are prefetched.
    public static let prefetchRadius = 10

    /// The scan of this app session; its selection store holds the groups.
    public let scan: ScanViewModel
    /// Which groups are shown.
    public var filter: Filter = .all
    /// How the groups are ordered. Switching to size sort computes the order at once.
    public var sort: Sort = .date {
        didSet {
            guard sort != oldValue else { return }
            applySizeOrder()
        }
    }
    /// Whether the user is touching or scrolling the list.
    public private(set) var isInteracting = false
    /// Creation dates of the members that were looked up.
    public internal(set) var photoDates: [String: Date] = [:]
    /// Members that no longer exist in the library (deleted outside the app); their cells show a placeholder.
    public internal(set) var missingAssetIDs: Set<String> = []
    /// The group waiting for "Delete every photo of this group?" to be confirmed.
    public var pendingDeleteAllClusterID: String?
    /// The last delete request, until the deletion flow handles it.
    public var deletionRequest: DeletionRequest?

    /// The order used by size sort, as last applied.
    private(set) var sizeOrder: [String] = []

    @ObservationIgnored let library: any PhotoLibraryRepository
    @ObservationIgnored let sizes: any AssetSizeEstimator
    @ObservationIgnored let thumbnails: any ThumbnailLoading
    @ObservationIgnored let libraryChanges: any LibraryChangeObserving
    @ObservationIgnored var memberSizes: [String: Int64] = [:]
    @ObservationIgnored var unavailableSizes: Set<String> = []
    @ObservationIgnored var requestedMetadata: Set<String> = []
    @ObservationIgnored var requestedSizes: Set<String> = []
    @ObservationIgnored var prefetchedIDs: Set<String> = []
    @ObservationIgnored var loads: [Task<Void, Never>] = []
    @ObservationIgnored var prefetchTask: Task<Void, Never>?
    @ObservationIgnored var thumbnailPixelSize = CGSize(
        width: ClusterListViewModel.thumbnailSide * 3,
        height: ClusterListViewModel.thumbnailSide * 3
    )

    /// Creates the view model.
    /// - Parameters:
    ///   - scan: The scan of this app session.
    ///   - library: Looks up the members' dates and which of them still exist.
    ///   - sizes: File sizes for the reclaimable-size sort.
    ///   - thumbnails: The thumbnail cache to prefetch into.
    ///   - libraryChanges: Library changes while the list is visible; each one re-checks which photos still exist.
    public init(
        scan: ScanViewModel,
        library: any PhotoLibraryRepository,
        sizes: any AssetSizeEstimator,
        thumbnails: any ThumbnailLoading,
        libraryChanges: any LibraryChangeObserving
    ) {
        self.scan = scan
        self.library = library
        self.sizes = sizes
        self.thumbnails = thumbnails
        self.libraryChanges = libraryChanges
    }

    /// The selection store of the scan.
    public var selection: SelectionStore { scan.selection }

    // MARK: - Rows

    /// The cluster IDs to show, top first.
    public var rows: [String] {
        let order = sort == .date ? displayOrder : sizeOrder
        return order.filter(matchesFilter)
    }

    /// The scan's row order without removed groups, followed by groups that reached the store another way.
    var displayOrder: [String] {
        let ordered = scan.rowOrder.ids.filter { selection.state(for: $0) != nil }
        let known = Set(ordered)
        return ordered + selection.clusterIDs.filter { !known.contains($0) }
    }

    /// The card of one group, or `nil` if the group is gone.
    public func card(for clusterID: String) -> ClusterCardModel? {
        guard let state = selection.state(for: clusterID) else { return nil }
        let photos = state.memberIDs.map { id in
            ClusterCardModel.Photo(id: id, date: photoDates[id], isMissing: missingAssetIDs.contains(id))
        }
        return ClusterCardModel(
            id: clusterID,
            photos: photos,
            isExactDuplicate: state.suggestion.cluster.isExactDuplicate,
            needsReview: state.needsReview
        )
    }

    /// "Still scanning… 4,210 of 18,000" while a scan runs, else `nil`.
    public var scanFooterText: String? {
        guard scan.isScanning else { return nil }
        let processed = scan.progress?.processed ?? 0
        let total = scan.progress?.total ?? 0
        return String(localized: "clusters.footer.scanning \(processed) \(total)", bundle: .module)
    }

    // MARK: - Sorting while scrolling

    /// The user started or stopped touching the list. When they stop, groups that arrived meanwhile are put at
    /// their sorted position.
    public func interactionChanged(isInteracting: Bool) {
        guard self.isInteracting != isInteracting else { return }
        self.isInteracting = isInteracting
        if !isInteracting {
            applySizeOrder()
        }
    }

    /// Recomputes the size order, unless the user is touching the list (then it waits for the scroll to end).
    func applySizeOrderIfIdle() {
        guard !isInteracting else { return }
        applySizeOrder()
    }

    /// Sorts by reclaimable size (unknown last), ties in row order. Does nothing under date sort.
    private func applySizeOrder() {
        guard sort == .reclaimableSize else { return }
        let order = displayOrder
        var position: [String: Int] = [:]
        for (index, id) in order.enumerated() {
            position[id] = index
        }
        let bytes = Dictionary(uniqueKeysWithValues: order.map { ($0, reclaimableBytes(of: $0) ?? -1) })
        let sorted = order.sorted { lhs, rhs in
            let left = bytes[lhs] ?? -1
            let right = bytes[rhs] ?? -1
            if left != right { return left > right }
            return (position[lhs] ?? 0) < (position[rhs] ?? 0)
        }
        if sorted != sizeOrder {
            sizeOrder = sorted
        }
    }

    /// Whether the group exists and passes the filter.
    private func matchesFilter(_ clusterID: String) -> Bool {
        guard let state = selection.state(for: clusterID) else { return false }
        switch filter {
        case .all:
            return true
        case .needsReview:
            return state.needsReview
        case .exactDuplicates:
            return state.suggestion.cluster.isExactDuplicate
        }
    }

    // MARK: - Selection

    /// Tapping a thumbnail: selects or keeps the photo. Selecting the last kept photo asks for confirmation first;
    /// a photo that no longer exists can't be selected.
    public func toggle(_ assetID: String, in clusterID: String) {
        guard !missingAssetIDs.contains(assetID) else { return }
        if selection.toggle(assetID, in: clusterID) == .needsConfirmation {
            pendingDeleteAllClusterID = clusterID
        }
    }

    /// The user confirmed deleting every photo of the pending group.
    public func confirmDeleteAll() {
        guard let clusterID = pendingDeleteAllClusterID else { return }
        pendingDeleteAllClusterID = nil
        selection.confirmDeleteAll(clusterID)
    }

    /// The bottom bar's delete button: records what is selected for the deletion flow (SPS-25), without photos
    /// that no longer exist. Nothing is deleted.
    public func requestDeletion() {
        let selected = selection.selectedAssetIDs.filter { !missingAssetIDs.contains($0) }
        guard !selected.isEmpty else { return }
        deletionRequest = DeletionRequest(assetIDs: selected)
    }
}
