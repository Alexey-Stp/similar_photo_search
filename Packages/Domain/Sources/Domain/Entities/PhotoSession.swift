import Foundation

/// A shooting session: a run of photos where every gap between neighbouring shots is at most
/// `SessionConfig.sessionGap`.
///
/// Sessions are the only unit that is ever compared (clustering) and the unit of live results.
public struct PhotoSession: Sendable, Hashable, Identifiable {
    /// Stable identifier: the newest photo's `localIdentifier` and its `creationDate` in milliseconds since 1970,
    /// as `"<id>@<milliseconds>"`. The same photos give the same ID on every run, so cached results can be matched.
    /// It names the session's newest photo, not its full membership: a deleted older photo keeps the ID.
    public let id: String
    /// The photos in `PhotoAsset.libraryOrder` (newest first). Every one has a `creationDate`.
    public let assets: [PhotoAsset]
    /// From the oldest to the newest `creationDate` in the session.
    public let dateRange: ClosedRange<Date>
    /// Whether the session has at least two photos. Single-photo sessions never reach Vision.
    public var needsAnalysis: Bool { assets.count >= 2 }

    /// Creates a session from photos in `PhotoAsset.libraryOrder`.
    ///
    /// Returns `nil` if `assets` is empty or any photo has no `creationDate`.
    public init?(assets: [PhotoAsset]) {
        guard let newest = assets.first,
              let newestDate = newest.creationDate,
              let oldestDate = assets.last?.creationDate,
              assets.allSatisfy({ $0.creationDate != nil }) else {
            return nil
        }
        self.id = Self.id(newestID: newest.id, newestDate: newestDate)
        self.assets = assets
        self.dateRange = min(oldestDate, newestDate)...max(oldestDate, newestDate)
    }

    /// The session ID for a session whose newest photo is `newestID`, taken at `newestDate`.
    public static func id(newestID: String, newestDate: Date) -> String {
        let milliseconds = (newestDate.timeIntervalSince1970 * 1_000).rounded()
        return "\(newestID)@\(Int64(exactly: milliseconds) ?? 0)"
    }
}
