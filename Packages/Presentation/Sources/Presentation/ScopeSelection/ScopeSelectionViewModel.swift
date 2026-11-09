import Domain
import Foundation
import Observation

/// Drives the "Scan scope" sheet: which albums, which dates, and whether screenshots are skipped.
///
/// No selected album means All Photos. Album IDs that no longer exist (for example albums deleted
/// outside the app) are dropped silently when the sheet loads, and the cleaned choice is saved.
/// Under limited access an album that can't be fetched may still exist, so its ID is kept, not dropped.
@Observable
@MainActor
public final class ScopeSelectionViewModel {
    /// The date presets offered in the sheet.
    public enum DatePreset: String, CaseIterable, Sendable, Identifiable {
        /// No date filter.
        case anyTime
        /// Today and the 29 days before it.
        case last30Days
        /// Since January 1.
        case thisYear
        /// A range the user picks.
        case custom

        /// Stable identity for `ForEach` and `Picker`.
        public var id: String { rawValue }
    }

    /// Whether the saved choice and the album list have been loaded.
    public private(set) var isLoaded = false
    /// Favorites, Selfies and Portrait (those that exist). Recents is left out: it is the same as All Photos.
    public private(set) var smartAlbums: [AlbumSummary] = []
    /// The user's own albums.
    public private(set) var userAlbums: [AlbumSummary] = []
    /// IDs of the selected albums. Empty means All Photos.
    public private(set) var selectedAlbumIDs: Set<String> = []
    /// The selected date preset.
    public private(set) var datePreset: DatePreset = .anyTime
    /// First day of the custom range. Always on or before `customEnd`.
    public private(set) var customStart: Date
    /// Last day of the custom range (inclusive). Always on or after `customStart`.
    public private(set) var customEnd: Date
    /// Whether screenshots are skipped. On by default.
    public private(set) var excludeScreenshots = true
    /// Photo count for the current choice, or `nil` before the first count finishes.
    /// With several overlapping albums it is an upper bound, so the UI shows it as "about".
    public private(set) var estimatedCount: Int?
    /// Whether a new count is being computed.
    public private(set) var isCounting = false

    /// Whether the whole library is selected.
    public var isAllPhotos: Bool {
        selectedAlbumIDs.isEmpty && unverifiedAlbumIDs.isEmpty
    }

    /// The current choice, with albums in list order (smart albums, then the user's albums), followed by
    /// saved albums that can't be checked under limited access.
    public var preferences: ScopePreferences {
        let listedIDs = (smartAlbums + userAlbums).map(\.id).filter(selectedAlbumIDs.contains)
        let orderedIDs = listedIDs + unverifiedAlbumIDs.sorted()
        return ScopePreferences(
            albumIDs: orderedIDs.isEmpty ? nil : orderedIDs,
            dateFilter: dateFilter,
            excludeScreenshots: excludeScreenshots,
            includeBursts: includeBursts
        )
    }

    private let library: any PhotoLibraryRepository
    private let permissions: any PhotoPermissionService
    private let store: any ScopePreferencesStore
    private let onApply: @MainActor (ScopePreferences) -> Void
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let countDebounce: Duration
    /// Not shown in the sheet; kept so saving does not reset it.
    private var includeBursts = false
    /// Saved album IDs that weren't listed while access is limited. They may belong to albums the app can't see
    /// right now, so they are kept until full access shows whether they still exist. Cleared by "All Photos".
    private var unverifiedAlbumIDs: Set<String> = []
    /// The saved custom range, used unchanged until the user edits the custom days, so loading the sheet in
    /// another time zone neither shifts nor widens it.
    private var savedCustomRange: ClosedRange<Date>?
    private var countTask: Task<Void, Never>?

    /// Creates the view model.
    /// - Parameters:
    ///   - library: Lists albums and counts photos.
    ///   - permissions: Tells whether access is full, so missing albums can be treated as deleted.
    ///   - store: Loads and saves the choice.
    ///   - onApply: Called after Apply has saved the choice, for example to close the sheet.
    ///   - now: The current time; injectable for tests.
    ///   - calendar: Used for day boundaries of the date presets.
    ///   - countDebounce: How long to wait after the last change before counting photos.
    public init(
        library: any PhotoLibraryRepository,
        permissions: any PhotoPermissionService,
        store: any ScopePreferencesStore,
        onApply: @escaping @MainActor (ScopePreferences) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        countDebounce: Duration = .milliseconds(300)
    ) {
        self.library = library
        self.permissions = permissions
        self.store = store
        self.onApply = onApply
        self.now = now
        self.calendar = calendar
        self.countDebounce = countDebounce
        let today = calendar.startOfDay(for: now())
        customEnd = today
        customStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
    }

    /// Loads the saved choice and the albums, drops albums that no longer exist, and starts counting.
    /// If album IDs had to be cleaned up, the saved choice is updated right away; nothing else is re-saved on load.
    public func load() async {
        let stored = await store.load()
        let albums = await library.albums()
        // Under limited access a missing album may just be invisible, so only full access can prove it was deleted.
        let canVerifyAlbums = await permissions.currentStatus() == .authorized
        smartAlbums = albums.filter { $0.kind != .user && $0.kind != .recents }
        userAlbums = albums.filter { $0.kind == .user }

        let knownIDs = Set((smartAlbums + userAlbums).map(\.id))
        let storedIDs = Set(stored.albumIDs ?? [])
        selectedAlbumIDs = storedIDs.intersection(knownIDs)
        unverifiedAlbumIDs = canVerifyAlbums ? [] : storedIDs.subtracting(knownIDs)
        excludeScreenshots = stored.excludeScreenshots
        includeBursts = stored.includeBursts
        restore(stored.dateFilter)
        isLoaded = true

        // Save only when albums were actually dropped (or duplicates collapsed), never just because the sheet opened.
        let keptIDs = preferences.albumIDs
        if (keptIDs ?? []).count != (stored.albumIDs ?? []).count || Set(keptIDs ?? []) != storedIDs {
            var cleaned = stored
            cleaned.albumIDs = keptIDs
            await store.save(cleaned)
        }
        scheduleCount()
    }

    /// Whether the album is selected.
    public func isSelected(_ albumID: String) -> Bool {
        selectedAlbumIDs.contains(albumID)
    }

    /// Selects or deselects an album. Deselecting the last album goes back to All Photos.
    public func toggle(_ albumID: String) {
        if selectedAlbumIDs.remove(albumID) == nil {
            selectedAlbumIDs.insert(albumID)
        }
        scheduleCount()
    }

    /// Selects the whole library, also dropping albums kept only because access is limited.
    public func selectAllPhotos() {
        guard !isAllPhotos else { return }
        selectedAlbumIDs.removeAll()
        unverifiedAlbumIDs.removeAll()
        scheduleCount()
    }

    /// Changes the date preset.
    public func setDatePreset(_ preset: DatePreset) {
        guard preset != datePreset else { return }
        datePreset = preset
        scheduleCount()
    }

    /// Changes the first day of the custom range; moves the last day forward if needed.
    public func setCustomStart(_ date: Date) {
        savedCustomRange = nil
        customStart = calendar.startOfDay(for: date)
        if customEnd < customStart {
            customEnd = customStart
        }
        if datePreset == .custom {
            scheduleCount()
        }
    }

    /// Changes the last day of the custom range; moves the first day back if needed.
    public func setCustomEnd(_ date: Date) {
        savedCustomRange = nil
        customEnd = calendar.startOfDay(for: date)
        if customStart > customEnd {
            customStart = customEnd
        }
        if datePreset == .custom {
            scheduleCount()
        }
    }

    /// Turns skipping screenshots on or off.
    public func setExcludeScreenshots(_ exclude: Bool) {
        guard exclude != excludeScreenshots else { return }
        excludeScreenshots = exclude
        scheduleCount()
    }

    /// Saves the choice and calls `onApply`.
    public func apply() async {
        let chosen = preferences
        await store.save(chosen)
        onApply(chosen)
    }

    /// Stops a count that is waiting or running. Call when the sheet is dismissed.
    public func cancelPendingCount() {
        countTask?.cancel()
        countTask = nil
        isCounting = false
    }

    /// Waits until the latest scheduled count has finished or was cancelled. For tests.
    public func waitForPendingCount() async {
        await countTask?.value
    }

    /// The date filter for the current preset. A custom range covers whole days: from the start of the first day
    /// up to the last instant before the day after the last one starts, so fractional seconds are included.
    private var dateFilter: DateFilter {
        switch datePreset {
        case .anyTime:
            return .anyTime
        case .last30Days:
            return .last30Days
        case .thisYear:
            return .thisYear
        case .custom:
            if let savedCustomRange {
                return .custom(savedCustomRange)
            }
            let start = calendar.startOfDay(for: customStart)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd))
            let end = nextDay.map { Date(timeIntervalSinceReferenceDate: $0.timeIntervalSinceReferenceDate.nextDown) }
                ?? customEnd
            return .custom(start...max(start, end))
        }
    }

    /// Sets the preset (and the custom days) from a saved filter.
    private func restore(_ filter: DateFilter) {
        switch filter {
        case .anyTime:
            datePreset = .anyTime
        case .last30Days:
            datePreset = .last30Days
        case .thisYear:
            datePreset = .thisYear
        case .custom(let range):
            datePreset = .custom
            savedCustomRange = range
            customStart = calendar.startOfDay(for: range.lowerBound)
            customEnd = max(customStart, calendar.startOfDay(for: range.upperBound))
        }
    }

    /// Recounts the photos after `countDebounce`, cancelling a count that is still waiting or running.
    private func scheduleCount() {
        countTask?.cancel()
        let scope = preferences.scanScope(now: now(), calendar: calendar)
        let library = library
        let debounce = countDebounce
        isCounting = true
        countTask = Task { [weak self] in
            if debounce > .zero {
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let count = await library.assetCount(scope: scope)
            guard !Task.isCancelled, let self else { return }
            estimatedCount = count
            isCounting = false
        }
    }
}
