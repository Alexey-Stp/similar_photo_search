import Domain
import Foundation
import Observation
import SwiftUI

/// Screens pushed from Home.
public enum HomeRoute: Hashable, Sendable {
    /// The groups of similar photos.
    case clusters
}

/// The full-screen comparison of one group, presented over the group list (SPS-22).
public struct ComparisonRequest: Hashable, Sendable, Identifiable {
    /// The group to compare.
    public let clusterID: String

    /// The group ID.
    public var id: String { clusterID }

    /// Creates a request.
    public init(clusterID: String) {
        self.clusterID = clusterID
    }
}

/// The home dashboard: which state to show, the results summary, and when to scan.
///
/// - At launch, the stored clusters of the last scan are shown at once (without a suggestion), and an incremental
///   scan runs **silently**: Home keeps showing the results with a compact progress bar instead of the full
///   scanning state. The scan re-publishes the same groups with a suggestion.
/// - A library change while the app is in the foreground starts a silent scan, or one right after the running
///   scan; a change in the background starts one when the app comes back.
/// - "Start Scan" (and "Scan Again", "Try Again") show the full scanning state; pull-to-refresh is silent once there
///   are results.
@Observable
@MainActor
public final class HomeViewModel {
    /// What Home shows.
    public enum ViewState: Hashable, Sendable {
        /// Never scanned: "Start Scan".
        case idle
        /// A scan the user started is running.
        case scanning(ScanProgress, foundSoFar: Int)
        /// Groups to review.
        case results(HomeSummary)
        /// The last scan found nothing.
        case empty
        /// The last scan stopped with an error; groups found before it may still be there.
        case error(String)
    }

    /// The scan of this app session.
    public let scan: ScanViewModel
    /// The navigation path of Home.
    public var path: [HomeRoute] = []
    /// The comparison shown full screen, if any.
    public var comparison: ComparisonRequest?
    /// Whether the running scan is a silent refresh (results stay on screen).
    public private(set) var isRefreshingSilently = false
    /// Whether stored results of an earlier scan were loaded at launch.
    public private(set) var hasStoredResults = false

    @ObservationIgnored private let results: any ClusterRepository
    @ObservationIgnored private let libraryChanges: any LibraryChangeObserving
    @ObservationIgnored private var didLaunch = false
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var needsRescan = false
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// Creates the view model.
    /// - Parameters:
    ///   - scan: The scan of this app session.
    ///   - results: The stored clusters of earlier scans, shown at launch.
    ///   - libraryChanges: Library changes while the app runs; each one starts an incremental scan.
    public init(
        scan: ScanViewModel,
        results: any ClusterRepository,
        libraryChanges: any LibraryChangeObserving
    ) {
        self.scan = scan
        self.results = results
        self.libraryChanges = libraryChanges
        scan.onScanEnded = { [weak self] in self?.scanEnded() }
    }

    // MARK: - State

    /// Whether an earlier scan exists: results were stored, or a scan of this session completed.
    public var hasPreviousScan: Bool {
        hasStoredResults || scan.hasCompletedScan
    }

    /// The state to show.
    public var viewState: ViewState {
        let groups = scan.groupCount
        if scan.isScanning, !isRefreshingSilently {
            return .scanning(scan.progress ?? ScanProgress(), foundSoFar: groups)
        }
        if !scan.isScanning, let error = scan.errorText {
            return .error(error)
        }
        if groups > 0 {
            return .results(summary)
        }
        if hasPreviousScan {
            return .empty
        }
        return .idle
    }

    /// Whether a silent refresh runs (shown as a compact progress bar above the results).
    public var isRefreshing: Bool {
        scan.isScanning && isRefreshingSilently
    }

    /// The groups found, their reclaimable size and the last scan's skips.
    public var summary: HomeSummary {
        HomeSummary(selection: scan.selection, skipped: scan.progress?.skipped ?? [:])
    }

    // MARK: - Actions

    /// Shows the stored results and starts the silent incremental scan, once per app session. Also starts
    /// following library changes. Call when Home appears.
    public func launch() async {
        guard !didLaunch else { return }
        didLaunch = true
        startObservingLibrary()
        guard !scan.hasStartedScan else { return }
        let stored = await results.storedResults()
        // The user may have started a scan while the results were loading: that scan publishes them itself.
        guard !stored.isEmpty, !scan.hasStartedScan, scan.selection.clusterIDs.isEmpty else { return }
        hasStoredResults = true
        scan.showStoredResults(StoredSessionResult.launchSelections(from: stored))
        await startScan(silently: true)
    }

    /// "Start Scan", "Scan Again" or "Try Again": a scan with the full scanning state.
    public func startScan() async {
        await startScan(silently: false)
    }

    /// Pull-to-refresh: an incremental scan, silent once there are results. Does nothing while a scan runs.
    public func refresh() async {
        guard !scan.isScanning else { return }
        await startScan(silently: hasPreviousScan)
    }

    /// "Review" or "Review now": opens the group list (the scan goes on).
    public func review() {
        guard path.last != .clusters else { return }
        path.append(.clusters)
    }

    /// Opens the full-screen comparison of one group (the header of its card, or the VoiceOver action "Compare").
    public func compare(clusterID: String) {
        guard comparison == nil else { return }
        comparison = ComparisonRequest(clusterID: clusterID)
    }

    /// Follows the scene phase (background time for the scan, library changes made in the background).
    public func scenePhaseChanged(to phase: ScenePhase) {
        scan.scenePhaseChanged(to: phase)
        isForeground = phase == .active
        if isForeground {
            rescanIfNeeded()
        }
    }

    /// The photo library changed: rescan now, after the running scan, or when the app is in the foreground again.
    /// Only after an earlier scan; a library that was never scanned is left alone. The change caused by this app's
    /// own deletion is ignored: the deletion flow already updated the groups (SPS-25).
    func libraryDidChange() {
        guard hasPreviousScan, !scan.isOwnDeletionInProgress else { return }
        needsRescan = true
        rescanIfNeeded()
    }

    // MARK: - Private

    private func startScan(silently: Bool) async {
        isRefreshingSilently = silently
        await scan.startScan()
    }

    private func scanEnded() {
        isRefreshingSilently = false
        rescanIfNeeded()
    }

    /// Starts the pending silent scan if the app is in the foreground and no scan runs.
    private func rescanIfNeeded() {
        guard needsRescan, isForeground, !scan.isScanning else { return }
        needsRescan = false
        Task { await startScan(silently: true) }
    }

    private func startObservingLibrary() {
        let changes = libraryChanges.changes()
        observation = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.libraryDidChange()
            }
        }
    }
}
