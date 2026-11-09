import Foundation

/// What changed in the photo library since the last successful scan, as PhotoKit `localIdentifier`s.
///
/// The sets are library-wide and may name assets that are not photos or are outside the scan scope (a video, a
/// hidden photo); consumers only look up IDs they meet, so such IDs are harmless.
public struct LibraryDelta: Sendable, Hashable {
    /// Assets added since the last scan.
    public private(set) var inserted: Set<String>
    /// Assets changed since the last scan (edited, favorited, metadata changed). Never also in `inserted`.
    public private(set) var updated: Set<String>
    /// Assets deleted since the last scan. Their analysis records are evicted from the cache.
    public private(set) var deleted: Set<String>
    /// Why the change history could not be used, or `nil` for an incremental delta.
    public let fullRescanReason: FullRescanReason?

    /// Whether the change history was unavailable and the delta was built by a full diff (current photos against
    /// cached ones). `updated` is then always empty: edits show up only through the photos' modification dates,
    /// which the cache key and `SessionFingerprint` both contain.
    public var isFullRescanRequired: Bool { fullRescanReason != nil }

    /// Whether nothing changed and the history was usable.
    public var isEmpty: Bool {
        !isFullRescanRequired && inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }

    /// Creates a delta.
    ///
    /// IDs in `inserted` are removed from `updated`. An ID in both `inserted` (or `updated`) and `deleted` is kept
    /// only in `deleted`: use `record(inserted:updated:deleted:)` to apply changes in their order instead.
    public init(
        inserted: Set<String> = [],
        updated: Set<String> = [],
        deleted: Set<String> = [],
        fullRescanReason: FullRescanReason? = nil
    ) {
        self.inserted = inserted.subtracting(deleted)
        self.updated = updated.subtracting(inserted).subtracting(deleted)
        self.deleted = deleted
        self.fullRescanReason = fullRescanReason
    }

    /// Applies one change transaction, in the order PhotoKit reports them, so the sets describe the net result:
    /// - inserted, then updated → inserted;
    /// - inserted or updated, then deleted → deleted only (the photo is gone);
    /// - deleted, then inserted again (an undo through iCloud) → inserted.
    public mutating func record(inserted: Set<String>, updated: Set<String>, deleted: Set<String>) {
        self.deleted.subtract(inserted)
        self.inserted.formUnion(inserted)
        self.updated.subtract(inserted)

        self.updated.formUnion(updated.subtracting(self.inserted))

        self.inserted.subtract(deleted)
        self.updated.subtract(deleted)
        self.deleted.formUnion(deleted)
    }

    /// The fallback when the change history is unavailable: every current photo that has no analysis record is
    /// `inserted`, every record whose photo is gone is `deleted`, and `updated` stays empty.
    ///
    /// `cachedIDs` lists only analysed photos (single-photo sessions and iCloud-only photos are never cached), so
    /// `inserted` is larger than what really changed; that is why a full rescan compares sessions by
    /// `SessionFingerprint` only and ignores `inserted`.
    public static func fullDiff(
        currentIDs: Set<String>,
        cachedIDs: Set<String>,
        reason: FullRescanReason
    ) -> LibraryDelta {
        LibraryDelta(
            inserted: currentIDs.subtracting(cachedIDs),
            deleted: cachedIDs.subtracting(currentIDs),
            fullRescanReason: reason
        )
    }
}

/// Why a scan could not use the library's change history and fell back to a full diff.
public enum FullRescanReason: String, Sendable, Hashable, CaseIterable {
    /// No scan has completed yet, so there is no token to start from.
    case noBaseline
    /// The stored token is older than the history PhotoKit keeps (`PHPhotosError.persistentChangeTokenExpired`).
    case tokenExpired
    /// The history exists but its details were truncated (`PHPhotosError.persistentChangeDetailsUnavailable`).
    case detailsUnavailable
    /// The stored token could not be decoded, or reading the history failed for another reason.
    case historyUnreadable
}

/// What `LibraryChangeTracker` found at the start of a scan.
public enum LibraryChangeReport: Sendable, Hashable {
    /// The changes since the last completed scan. Its `fullRescanReason` is `nil`.
    case changes(LibraryDelta)
    /// The history can't be used; `currentAssetIDs` are all photos in the library (images, hidden ones excluded),
    /// for the full diff against the cache.
    case historyUnavailable(FullRescanReason, currentAssetIDs: Set<String>)
}
