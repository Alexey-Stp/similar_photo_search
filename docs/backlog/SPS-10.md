# SPS-10 — Incremental library change tracking

**Type:** Technical task · **Epic:** SPS-6 · **Depends on:** SPS-13, SPS-26

## Description

Avoid re-analysing the whole library on every launch. Use `PHPhotoLibrary` persistent change tokens to find inserted,
updated and deleted assets since the last successful scan.

## Acceptance criteria

- After a successful scan, store `PHPhotoLibrary.shared().currentChangeToken` (archived via `NSKeyedArchiver`;
  `PHPersistentChangeToken` supports `NSSecureCoding`).
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
