import Foundation

/// The scan scope as the user chose it, saved between launches.
///
/// Unlike `ScanScope`, the date filter is stored as a preset ("Last 30 days"), not as fixed dates,
/// so it stays current. Call `scanScope(now:calendar:)` to resolve it right before a scan.
public struct ScopePreferences: Sendable, Hashable, Codable {
    /// Local identifiers of the selected albums, or `nil` for All Photos.
    public var albumIDs: [String]?
    /// Which photos are kept by date.
    public var dateFilter: DateFilter
    /// Whether screenshots are left out.
    public var excludeScreenshots: Bool
    /// Whether every photo of a burst is scanned. When `false`, only each burst's representative is.
    public var includeBursts: Bool

    /// Creates preferences. The defaults scan the whole library at any date, without screenshots or extra burst frames.
    public init(
        albumIDs: [String]? = nil,
        dateFilter: DateFilter = .anyTime,
        excludeScreenshots: Bool = true,
        includeBursts: Bool = false
    ) {
        self.albumIDs = albumIDs
        self.dateFilter = dateFilter
        self.excludeScreenshots = excludeScreenshots
        self.includeBursts = includeBursts
    }

    /// All Photos, any date, screenshots skipped.
    public static let `default` = ScopePreferences()

    /// The scope to scan, with the date preset resolved against `now`.
    public func scanScope(now: Date, calendar: Calendar) -> ScanScope {
        ScanScope(
            albumIDs: albumIDs,
            dateRange: dateFilter.range(now: now, calendar: calendar),
            excludeScreenshots: excludeScreenshots,
            includeBursts: includeBursts
        )
    }
}

/// A date filter for the scan scope.
public enum DateFilter: Sendable, Hashable, Codable {
    /// No date filter; photos without a date are scanned too.
    case anyTime
    /// Today and the 29 days before it.
    case last30Days
    /// From January 1 of the current year.
    case thisYear
    /// A fixed, inclusive range.
    case custom(ClosedRange<Date>)

    /// The inclusive date range this filter stands for at `now`, or `nil` for `anyTime`.
    ///
    /// Presets end at `now`; they start at the beginning of a day in `calendar`'s time zone.
    public func range(now: Date, calendar: Calendar) -> ClosedRange<Date>? {
        switch self {
        case .anyTime:
            return nil
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return start...max(start, now)
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            return start...max(start, now)
        case .custom(let range):
            return range
        }
    }
}
