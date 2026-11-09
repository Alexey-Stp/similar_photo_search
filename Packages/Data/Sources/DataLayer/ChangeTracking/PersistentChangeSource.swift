import Domain
import Foundation

/// Why PhotoKit's persistent change history could not be read.
enum PersistentChangeError: Error, Sendable, Hashable {
    /// `PHPhotosError.persistentChangeTokenExpired`.
    case tokenExpired
    /// `PHPhotosError.persistentChangeDetailsUnavailable`.
    case detailsUnavailable
    /// The stored token could not be decoded.
    case unreadableToken
    /// Any other error from PhotoKit.
    case other

    /// The reason reported for the full-diff fallback.
    var fullRescanReason: FullRescanReason {
        switch self {
        case .tokenExpired: .tokenExpired
        case .detailsUnavailable: .detailsUnavailable
        case .unreadableToken, .other: .historyUnreadable
        }
    }
}

/// The PhotoKit calls `PhotoKitLibraryChangeTracker` needs. Tokens travel as archived `Data`, so the tracker and its
/// tests never touch `PHPersistentChangeToken`.
protocol PersistentChangeSource: Sendable {
    /// The library's current change token, archived with `NSKeyedArchiver` (secure coding), or `nil` if it can't be
    /// archived.
    func currentToken() -> Data?

    /// The net asset changes since `token` (an archive made by `currentToken()`).
    ///
    /// Throws `PersistentChangeError` if the history can't be read, `CancellationError` if the task is cancelled.
    func assetChanges(since token: Data) throws -> LibraryDelta

    /// The `localIdentifier` of every image in the library, burst members included, hidden ones excluded.
    ///
    /// Throws `CancellationError` if the task is cancelled.
    func allAssetIDs() throws -> Set<String>
}
