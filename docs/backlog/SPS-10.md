# SPS-10 — Incremental library change tracking

**Type:** Technical task · **Epic:** SPS-6 · **Depends on:** SPS-13, SPS-26

## Description

Avoid re-analysing the whole library on every launch. Use `PHPhotoLibrary` persistent change tokens to find inserted,
updated and deleted assets since the last successful scan.

## Acceptance criteria

- At the start of a scan, read `PHPhotoLibrary.shared().currentChangeToken` **before** computing the delta or enumerating
  the library. After the scan succeeds, persist that start token (archived via `NSKeyedArchiver`; `PHPersistentChangeToken`
  supports `NSSecureCoding`), never the token current at the end: changes made while the scan ran are then picked up by the
  next scan instead of being skipped.
- On the next scan, `fetchPersistentChanges(since:)` gives the inserted, updated and deleted local identifiers for
  `PHObjectType.asset`. Only those are queued for analysis or eviction.
- **Given** the token has expired (`PHPhotosError.persistentChangeTokenExpired`) or the details are truncated
  (`PHPhotosError.persistentChangeDetailsUnavailable`), **then** the app falls back to a full diff: all current IDs compared with cached IDs.
- **Given** an asset was edited (`updatedLocalIdentifiers`), **then** its cached feature print is invalidated.
- **Given** new photos were added, **then** only their own sessions are re-analysed and re-clustered; other sessions reuse cached results.
- Edge case: a new photo turns a single-photo session into a two-photo session, so the old photo now needs analysis for the first time.
- Edge case: a new photo falls between two sessions and closes the gap (both gaps ≤ `sessionGap`), so the sessions merge and are re-clustered together.
- A live `PHPhotoLibraryChangeObserver` updates visible clusters while the app is in the foreground (debounced 1 s).

## Technical notes

`PHPersistentChange.changeDetails(for: .asset)` returns `PHPersistentObjectChangeDetails`. Register the observer with
`PHPhotoLibrary.shared().register(_:)` and unregister in `deinit`. The callback comes on a background queue, so hop to the actor.
Writing the token file under Application Support: check whether any file-timestamp API is used (privacy manifest).

## Risks

The change-token history is limited and expires after heavy edits, so the fallback path must be solid. The observer callback
runs off the main thread; touching view-model state directly causes data races.

## Implementation hints

- `actor LibraryChangeTracker` (Data) with `func changesSinceLastScan() async throws -> LibraryDelta` and `func commitScanCompleted()`.
- `struct LibraryDelta: Sendable { inserted: Set<String>; updated: Set<String>; deleted: Set<String>; isFullRescanRequired: Bool }`.
- Persist the token with `NSKeyedArchiver(requiringSecureCoding: true)` to Application Support.
- Map `.persistentChangeTokenExpired` and `.persistentChangeDetailsUnavailable` to `isFullRescanRequired = true`.
- `LiveLibraryObserver: NSObject, PHPhotoLibraryChangeObserver` exposing a debounced (1 s) `AsyncStream<Void>`.
- Tests: the error-to-fallback mapping; session merge and single→pair cases at the Domain level.
- From SPS-26: `PhotoSession.id` is the newest photo's id and timestamp, so it changes when a newer photo joins a session but not when an older one is added or removed; compare membership, not only IDs, to decide which cached session results are stale.
- From SPS-13: the full-diff fallback needs every cached ID, which `FeaturePrintCache` can't list yet: add `cachedAssetIDs() async -> Set<String>` (fetch with `propertiesToFetch = [\.assetID]`, never the vectors) and call `purge(assetIDs:)` for deleted IDs. An edited photo needs no purge: its new modification date already makes `validEntries` miss.

## Implementation notes

- **Split between tracker and use case.** `LibraryChangeTracker` (Domain protocol) returns a `LibraryChangeReport`:
  `.changes(LibraryDelta)` or `.historyUnavailable(FullRescanReason, currentAssetIDs:)`. The Domain use case
  `IncrementalScanPreparer.prepare()` turns that into the final `LibraryDelta` (full diff against
  `FeaturePrintCache.cachedAssetIDs()` in the fallback) and purges `deleted` from the cache (a failed purge is
  ignored). The coordinator calls `prepare()` first and `tracker.commitScanCompleted()` only after a successful scan.
- `LibraryDelta` has `fullRescanReason: FullRescanReason?` (`noBaseline`, `tokenExpired`, `detailsUnavailable`,
  `historyUnreadable`); `isFullRescanRequired` is derived from it. Every history problem falls back, not only the two
  named codes; only `CancellationError` is thrown. The first scan (no saved token) is a `noBaseline` full diff.
  Changes are accumulated in PhotoKit order with `LibraryDelta.record(inserted:updated:deleted:)` (net result:
  inserted→deleted is only deleted, deleted→inserted is inserted, inserted→updated stays inserted).
- **Edited photos are not purged** (as the SPS-13 note said): the new modification date makes `validEntries` miss.
  An update that keeps the date (some metadata changes) keeps the print but still re-clusters the session.
- **Which sessions to redo: `SessionChangePlanner` + `SessionFingerprint`** (Domain, pure). A fingerprint is the
  session ID plus `Content` (member count + FNV-1a 64 digest over every member's ID, modification date and favorite
  flag, in library order; stable across launches, `Codable`). `classify(_:)` gives `.unchanged` only if a previous
  session had the same content and (incremental delta only) no member is in `inserted ∪ updated`; `staleSessionIDs`
  lists previous sessions not reused. Single→pair, merges, splits, deletions and edits all change the content, so they
  come out `.changed`; the feature-print cache still decides per photo which ones reach Vision. On a full rescan
  `inserted` is ignored (it lists every uncached photo, including single-photo sessions and iCloud-only skips).
- **Nothing stores fingerprints yet.** There is no cluster store; SPS-14 must save each session's `SessionFingerprint`
  with its results and pass the previous ones to the planner (none after a session-config change).
- Data: `PhotoKitLibraryChangeTracker` (actor) over an internal `PersistentChangeSource` (`PhotoKitPersistentChangeSource`
  in production, a fake in tests); tokens cross the boundary as `NSKeyedArchiver` `Data`. The token file is
  `Application Support/ChangeTracking/LastScan.token`, written atomically with
  `.completeFileProtectionUntilFirstUserAuthentication`, directory excluded from backup. No file dates are read, so the
  privacy manifest is unchanged. The full-diff ID list fetches all images with `includeAllBurstAssets = true` (burst
  members can be cached) and hidden ones excluded, 1,000 IDs per `autoreleasepool`.
- Live updates: `LibraryChangeObserving.changes() -> AsyncStream<Void>` (Domain), implemented by
  `PhotoKitLibraryObserver`, which registers with PhotoKit on the first `changes()` call (never at launch, so no
  prompt before onboarding) and unregisters in `deinit`. The debounce is the Domain `DebouncedSignal` (trailing, 1 s,
  every stream gets every event, at most one buffered). Nothing consumes the stream yet: SPS-14/SPS-20 should run an
  incremental scan on each event while the scan screen is in the foreground.
- `AppContainer` builds `libraryChangeTracker`, `incrementalScanPreparer` and `libraryObserver`; no caller yet.
- **Not verified on this branch (Windows):** `Packages/Data` build and tests (`PhotoKitLibraryChangeTrackerTests`,
  `cachedAssetIDsListsEveryRecord`), the app build, SwiftLint and `check-privacy-manifest.sh` (needs `plutil`; a manual
  scan of the changed sources for required-reason API patterns found none). Unverified API assumption: iterating
  `PHPersistentChangeFetchResult` with `for … in` (as in Apple's WWDC22 sample). **Device QA still open:** edit, add and
  delete photos in Photos between two scans and check the logged delta; force a fallback by deleting the token file;
  check that the observer fires once ~1 s after a burst of changes, and that persistent changes work under Limited access.
