import Domain
import Foundation
import os

/// `LibraryChangeTracker` over PhotoKit's persistent change history (`PHPhotoLibrary.fetchPersistentChanges(since:)`).
///
/// `changesSinceLastScan()` reads the library's current token first and keeps it as this scan's start token;
/// `commitScanCompleted()` saves that start token to Application Support/ChangeTracking. Any problem with the
/// history (no saved token, expired token, truncated details, unreadable token, other PhotoKit errors) becomes
/// `.historyUnavailable` with every current photo ID, for the full diff.
public actor PhotoKitLibraryChangeTracker: LibraryChangeTracker {
    private static let logger = Logger(subsystem: "com.similarphotos", category: "changeTracking")

    private let source: any PersistentChangeSource
    private let tokenStore: ChangeTokenStore
    private var startToken: Data?

    /// Creates the app's tracker. Touches neither PhotoKit nor the disk until a scan starts.
    public init() {
        self.init(source: PhotoKitPersistentChangeSource(), tokenStore: ChangeTokenStore())
    }

    /// Creates a tracker over `source` that saves tokens in `tokenStore`.
    init(source: any PersistentChangeSource, tokenStore: ChangeTokenStore) {
        self.source = source
        self.tokenStore = tokenStore
    }

    /// The changes since the last committed scan; remembers the current token as this scan's start token first.
    public func changesSinceLastScan() async throws -> LibraryChangeReport {
        startToken = source.currentToken()
        if startToken == nil {
            Self.logger.error("Could not archive the current change token; this scan will not be committed")
        }
        guard let savedToken = tokenStore.load() else {
            return .historyUnavailable(.noBaseline, currentAssetIDs: try source.allAssetIDs())
        }
        do {
            let delta = try source.assetChanges(since: savedToken)
            Self.logger.info("""
                Library changes: \(delta.inserted.count, privacy: .public) inserted, \
                \(delta.updated.count, privacy: .public) updated, \(delta.deleted.count, privacy: .public) deleted
                """)
            return .changes(delta)
        } catch let error as PersistentChangeError {
            let reason = error.fullRescanReason
            Self.logger.notice("Change history unavailable (\(reason.rawValue, privacy: .public)), doing a full diff")
            return .historyUnavailable(reason, currentAssetIDs: try source.allAssetIDs())
        }
    }

    /// Saves the start token of the last `changesSinceLastScan()`, then forgets it. Does nothing without one.
    public func commitScanCompleted() async throws {
        guard let startToken else { return }
        try tokenStore.save(startToken)
        self.startToken = nil
    }
}
