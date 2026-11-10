import Domain
import Foundation
import SwiftUI

/// Drives a library scan from the UI: starts and cancels it, consumes its progress and group streams, feeds the
/// groups into `SelectionStore` (append-only), and handles the app lifecycle around it.
///
/// - The screen stays awake only while the scan screen is visible **and** a scan runs.
/// - In the background the scan keeps going for the time iOS grants (`beginBackgroundTask`); when that runs out it
///   is cancelled, which saves what was finished.
@Observable
@MainActor
public final class ScanViewModel {
    /// The latest progress snapshot, or `nil` before the first scan.
    public private(set) var progress: ScanProgress?
    /// Whether a scan is running.
    public private(set) var isScanning = false

    /// The keep / delete choice; groups arrive here in publishing order.
    public let selection: SelectionStore

    @ObservationIgnored private let coordinator: any ScanCoordinating
    @ObservationIgnored private let preferences: any ScopePreferencesStore
    @ObservationIgnored private let idleTimer: any IdleTimerControlling
    @ObservationIgnored private let backgroundTasks: any BackgroundTaskRunning
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var consumers: [Task<Void, Never>] = []
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var isScanScreenVisible = false
    @ObservationIgnored private var backgroundTask: BackgroundTaskToken?

    /// Creates the view model.
    public init(
        coordinator: any ScanCoordinating,
        preferences: any ScopePreferencesStore,
        selection: SelectionStore,
        idleTimer: any IdleTimerControlling,
        backgroundTasks: any BackgroundTaskRunning,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.selection = selection
        self.idleTimer = idleTimer
        self.backgroundTasks = backgroundTasks
        self.now = now
        self.calendar = calendar
    }

    // MARK: - Actions

    /// Starts a scan with the saved scope and session gap. A running scan is replaced.
    public func startScan() async {
        let saved = await preferences.load()
        scanGeneration += 1
        let generation = scanGeneration
        stopConsuming()
        isScanning = true
        progress = ScanProgress()
        updateIdleTimer()
        let streams = await coordinator.start(
            scope: saved.scanScope(now: now(), calendar: calendar),
            sessionConfig: saved.sessionConfig
        )
        guard generation == scanGeneration else { return }
        consumers = [
            Task { [weak self] in
                for await snapshot in streams.progress {
                    guard let self, generation == self.scanGeneration else { return }
                    self.progress = snapshot
                }
            },
            Task { [weak self] in
                for await update in streams.clusters {
                    guard let self, generation == self.scanGeneration else { return }
                    self.apply(update)
                }
            }
        ]
    }

    /// Cancels the running scan; groups found so far stay.
    public func cancelScan() {
        guard isScanning else { return }
        let coordinator = coordinator
        Task { await coordinator.cancel() }
    }

    /// Photos the user deleted (SPS-25 calls this after a successful deletion): the running scan never loads,
    /// analyses or publishes them. Updating the groups already shown is the deletion flow's job.
    public func photosDeleted(_ assetIDs: Set<String>) {
        guard !assetIDs.isEmpty else { return }
        let coordinator = coordinator
        Task { await coordinator.excludeDeleted(assetIDs) }
    }

    // MARK: - Lifecycle

    /// The scan screen became visible.
    public func scanScreenAppeared() {
        isScanScreenVisible = true
        updateIdleTimer()
    }

    /// The scan screen is no longer visible.
    public func scanScreenDisappeared() {
        isScanScreenVisible = false
        updateIdleTimer()
    }

    /// Follows the scene phase: asks for background time when the app leaves the foreground during a scan.
    public func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .background:
            beginBackgroundTaskIfNeeded()
        case .active:
            endBackgroundTask()
        case .inactive:
            break
        @unknown default:
            break
        }
        updateIdleTimer()
    }

    // MARK: - Display

    /// The completed share, for example "42 %".
    public var percentText: String {
        (progress?.fractionCompleted ?? 0).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "3,120 of 10,000 photos".
    public var countText: String {
        let processed = progress?.processed ?? 0
        let total = progress?.total ?? 0
        return String(localized: "scan.count \(processed) \(total)", bundle: .module)
    }

    /// "About 2 min left", or `nil` while there is no estimate.
    public var etaText: String? {
        guard isScanning, let eta = progress?.eta, eta > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = eta >= 3_600 ? [.hour, .minute] : (eta >= 60 ? [.minute] : [.second])
        formatter.maximumUnitCount = 2
        guard let duration = formatter.string(from: eta.rounded(.up)) else { return nil }
        return String(localized: "scan.eta \(duration)", bundle: .module)
    }

    /// Whether the scan is paused because the device is too hot ("Paused to cool down").
    public var isPausedToCoolDown: Bool {
        guard isScanning, let progress else { return false }
        return progress.phase == .throttled || progress.conditions.isPaused
    }

    /// Whether Low Power Mode slows the scan down (shown as a notice).
    public var isSlowedByLowPowerMode: Bool {
        isScanning && progress?.conditions.isLowPowerModeEnabled == true
    }

    /// Whether a scan was started in this app session (running, finished, cancelled or failed). `false` means the
    /// "never scanned" state.
    public var hasStartedScan: Bool {
        progress != nil
    }

    /// Groups found so far.
    public var groupCount: Int {
        selection.clusterIDs.count
    }

    /// The text of the last scan's error, or `nil`.
    public var errorText: String? {
        guard case .failed(let failure) = progress?.phase else { return nil }
        switch failure {
        case .missingThreshold:
            return String(localized: "scan.error.notCalibrated", bundle: .module)
        case .libraryUnavailable:
            return String(localized: "scan.error.library", bundle: .module)
        }
    }

    // MARK: - Private

    /// Applies one group change to the selection store.
    private func apply(_ update: ClusterUpdate) {
        switch update {
        case .added(let selections):
            selection.upsert(selections)
        case .removed(let ids):
            selection.remove(clusterIDs: ids)
        case .finished:
            scanEnded()
        }
    }

    /// The scan finished: lets the screen sleep again and gives back background time.
    private func scanEnded() {
        isScanning = false
        updateIdleTimer()
        endBackgroundTask()
    }

    /// Stops reading the streams of the previous scan.
    private func stopConsuming() {
        for consumer in consumers {
            consumer.cancel()
        }
        consumers = []
    }

    /// Keeps the screen awake only while the scan screen is visible and a scan runs.
    private func updateIdleTimer() {
        idleTimer.setIdleTimerDisabled(isScanScreenVisible && isScanning)
    }

    /// Asks for background time if a scan runs; on expiry the scan is cancelled.
    private func beginBackgroundTaskIfNeeded() {
        guard isScanning, backgroundTask == nil else { return }
        backgroundTask = backgroundTasks.beginBackgroundTask(named: "SimilarPhotos.scan") { [weak self] in
            // Must return quickly: cancel (the coordinator saves what is finished) and give the time back.
            self?.cancelScan()
            self?.endBackgroundTask()
        }
    }

    /// Gives back the background time, if any was granted.
    private func endBackgroundTask() {
        guard let token = backgroundTask else { return }
        backgroundTask = nil
        backgroundTasks.endBackgroundTask(token)
    }
}
