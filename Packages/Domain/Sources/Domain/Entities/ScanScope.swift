import Foundation

/// Which photos a scan looks at. Persisted between launches, so it is `Codable`.
public struct ScanScope: Sendable, Hashable, Codable {
    /// Local identifiers of the albums to scan, or `nil` for the whole library.
    /// An asset in several selected albums is delivered once. Unknown IDs are ignored.
    public var albumIDs: [String]?
    /// Only photos taken in this range (inclusive) are scanned. Photos without a date are then excluded.
    public var dateRange: ClosedRange<Date>?
    /// Whether screenshots are left out.
    public var excludeScreenshots: Bool
    /// Whether every photo of a burst is scanned. When `false`, only each burst's representative is.
    public var includeBursts: Bool

    /// Creates a scope. The defaults scan the whole library without screenshots or extra burst frames.
    public init(
        albumIDs: [String]? = nil,
        dateRange: ClosedRange<Date>? = nil,
        excludeScreenshots: Bool = true,
        includeBursts: Bool = false
    ) {
        self.albumIDs = albumIDs
        self.dateRange = dateRange
        self.excludeScreenshots = excludeScreenshots
        self.includeBursts = includeBursts
    }

    /// The whole library with the default filters.
    public static let allPhotos = ScanScope()
}
