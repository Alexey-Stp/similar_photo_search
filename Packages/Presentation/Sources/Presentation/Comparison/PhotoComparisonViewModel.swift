import Domain
import Foundation
import Observation

/// Drives the full-screen comparison of one group (SPS-22): which photo the pager shows, the two panes of the
/// side-by-side mode, the info panel, and the keep / delete actions, which apply to `SelectionStore` at once.
///
/// - The pager starts on the group's **Best** photo. Side by side, the left pane shows `shownCurrentID` and the right
///   pane `shownSecondaryID` (the Best photo, or the next one when the left pane shows the Best). The filmstrip puts
///   a photo into the focused pane.
/// - Memory: only the current photo and its neighbours load at screen size (`shouldLoadFullImage(_:)`); side by
///   side, only the two shown photos.
/// - The group is read live from the store, so a rescan that changes it updates the screen; when it disappears,
///   `isAvailable` turns false.
@Observable
@MainActor
public final class PhotoComparisonViewModel {
    /// A pane of the side-by-side mode.
    public enum Pane: Sendable, Hashable {
        /// The left pane, which also is the pager's page.
        case primary
        /// The right pane.
        case secondary
    }

    /// The group compared.
    public let clusterID: String
    /// The photo the user moved to (pager page or left pane); `nil` until they do, then the Best photo is shown.
    public var currentID: String? {
        didSet {
            if currentID != oldValue {
                pagerZoom.reset()
            }
        }
    }
    /// The photo the user put in the right pane, if any.
    public private(set) var secondaryID: String?
    /// The pane the info panel and the filmstrip act on, side by side.
    public private(set) var focusedPane = Pane.primary
    /// Whether the user wants two photos side by side when the screen is wide enough.
    public var prefersSideBySide = true
    /// Whether the screen is wide enough for two photos (regular width or compact height).
    public private(set) var canShowSideBySide = false
    /// Date, resolution, size, favorite, edited and Live of the members, once looked up.
    public internal(set) var infos: [String: ComparisonPhotoInfo] = [:]
    /// Members the library no longer has, found while looking them up.
    public internal(set) var notFoundIDs: Set<String> = []
    /// Whether "Delete every photo of this group?" is asked.
    public var isConfirmingDeleteAll = false
    /// The zoom of the pager's current page (reset on every page change).
    public let pagerZoom = ZoomState()
    /// The zoom both panes share side by side.
    public let sharedZoom = ZoomState()

    @ObservationIgnored let list: ClusterListViewModel
    @ObservationIgnored let screenImages: any ScreenImageLoading
    @ObservationIgnored let edits: any PhotoEditStatusProviding
    @ObservationIgnored var loadedMembers: [String] = []

    /// Creates the view model.
    /// - Parameters:
    ///   - clusterID: The group to compare.
    ///   - list: The group list of the app session: selection store, thumbnails, library and sizes.
    ///   - screenImages: Loads photos at screen size, local only.
    ///   - edits: Tells which photos have edits.
    public init(
        clusterID: String,
        list: ClusterListViewModel,
        screenImages: any ScreenImageLoading,
        edits: any PhotoEditStatusProviding
    ) {
        self.clusterID = clusterID
        self.list = list
        self.screenImages = screenImages
        self.edits = edits
    }

    // MARK: - Group

    /// The keep / delete choice of the session.
    public var selection: SelectionStore { list.selection }
    /// Thumbnails for the filmstrip.
    public var thumbnails: any ThumbnailLoading { list.thumbnails }
    /// Loads photos at screen size.
    public var screenImageLoader: any ScreenImageLoading { screenImages }
    /// The group's live choice, or `nil` once it is gone.
    public var state: ClusterSelectionState? { selection.state(for: clusterID) }
    /// The members, in library order (newest first).
    public var memberIDs: [String] { state?.memberIDs ?? [] }
    /// Whether the group still exists.
    public var isAvailable: Bool { !memberIDs.isEmpty }

    // MARK: - What is shown

    /// The photo of the pager (or the left pane): the one the user moved to, else the Best, else the first.
    public var shownCurrentID: String? {
        member(currentID) ?? member(state?.keeperID) ?? memberIDs.first
    }

    /// The photo of the right pane: the one the user put there, else the Best, else the one after the left photo.
    public var shownSecondaryID: String? {
        guard let current = shownCurrentID else { return nil }
        if let chosen = member(secondaryID), chosen != current {
            return chosen
        }
        return partner(of: current)
    }

    /// Whether two photos are shown side by side.
    public var showsSideBySide: Bool {
        canShowSideBySide && prefersSideBySide && memberIDs.count > 1
    }

    /// The photo the info panel describes and the actions apply to.
    public var focusedID: String? {
        showsSideBySide && focusedPane == .secondary ? shownSecondaryID : shownCurrentID
    }

    /// The zoom that is in use; while it is zoomed, a drag pans instead of dismissing.
    public var activeZoom: ZoomState { showsSideBySide ? sharedZoom : pagerZoom }

    /// Whether the photo should be held at screen size: the current photo and its neighbours in the pager, the two
    /// shown photos side by side. Every other photo releases its image.
    public func shouldLoadFullImage(_ assetID: String) -> Bool {
        if showsSideBySide {
            return assetID == shownCurrentID || assetID == shownSecondaryID
        }
        guard let current = shownCurrentID,
              let currentIndex = memberIDs.firstIndex(of: current),
              let index = memberIDs.firstIndex(of: assetID) else { return false }
        return abs(index - currentIndex) <= 1
    }

    /// "2 of 5" for a member.
    public func positionText(of assetID: String) -> String? {
        guard let index = memberIDs.firstIndex(of: assetID) else { return nil }
        return String(localized: "compare.position \(index + 1) \(memberIDs.count)", bundle: .module)
    }

    // MARK: - Navigation

    /// The screen's size classes changed.
    public func layoutChanged(canShowSideBySide: Bool) {
        guard self.canShowSideBySide != canShowSideBySide else { return }
        self.canShowSideBySide = canShowSideBySide
        sharedZoom.reset()
        pagerZoom.reset()
    }

    /// Tapping a pane side by side: the info panel and the filmstrip now act on it.
    public func focus(_ pane: Pane) {
        if focusedPane != pane {
            focusedPane = pane
        }
    }

    /// Tapping a filmstrip photo: shows it in the pager or the focused pane. Picking the photo of the other pane
    /// swaps the two.
    public func show(_ assetID: String) {
        guard memberIDs.contains(assetID) else { return }
        let current = shownCurrentID
        let secondary = shownSecondaryID
        if showsSideBySide, focusedPane == .secondary {
            if assetID == current {
                currentID = secondary
            }
            secondaryID = assetID
        } else {
            if showsSideBySide, assetID == secondary {
                secondaryID = current
            }
            currentID = assetID
        }
    }

    // MARK: - Private

    /// `assetID` if it is a member, else `nil`.
    private func member(_ assetID: String?) -> String? {
        guard let assetID, memberIDs.contains(assetID) else { return nil }
        return assetID
    }

    /// The default photo to compare `assetID` with: the Best, or the next member when it is the Best.
    private func partner(of assetID: String) -> String? {
        if let keeper = member(state?.keeperID), keeper != assetID {
            return keeper
        }
        guard let index = memberIDs.firstIndex(of: assetID), memberIDs.count > 1 else { return nil }
        return memberIDs[(index + 1) % memberIDs.count]
    }
}
