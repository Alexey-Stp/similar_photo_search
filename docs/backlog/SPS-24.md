# SPS-24 — `AssetDeletionService` via PhotoKit change requests

**Type:** Technical task · **Epic:** SPS-23 · **Depends on:** SPS-2

## Description

A service that deletes assets by local identifier and maps every outcome to a typed result.

## Acceptance criteria

- Re-fetch the assets with `PHAsset.fetchAssets(withLocalIdentifiers:options:)` right before deletion; missing IDs are reported as `failed[id] = .unavailable` (deleted elsewhere **or** no longer accessible, e.g. removed from
  Limited access) and are not counted as deleted. Only IDs this call deleted and the post-delete re-fetch no longer finds go into `deleted`.
- Filter with `asset.canPerform(.delete)`; non-deletable assets (for example in shared albums) are reported as `notDeletable` and excluded.
- Call `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(...) }` (async variant). iOS shows its
  own confirmation alert, so the app adds no second "Are you sure?" (SPS-25 has the pre-summary).
- **Given** the user taps "Don't Allow", **then** `PHPhotosError.userCancelled` (`PHPhotosErrorDomain`, code 3072) maps to
  `.cancelledByUser`. Nothing changes, and no error UI is shown.
- **Given** the access level is not `.readWrite` (for example revoked mid-session), **then** `.permissionDenied` is returned.
- Batching: one `performChanges` call, so the user sees one system alert. Chunking (up to 500 per call) only as a fallback
  after a failure, behind a feature flag. Decide after a device spike with 2,000 assets.
- Returns `DeletionResult { deleted: Set<String>; failed: [String: DeletionError]; cancelled: Bool }`.
- The zero-network manual QA ([docs/qa/zero-network.md](../qa/zero-network.md)) passes over a deletion.

## Technical notes

The `performChanges` block runs on an arbitrary queue: capture only `Sendable` data (identifiers) and re-fetch inside the
block. Under Limited access only accessible assets can be deleted; check this.

## Risks

Treating a user cancel as an error makes the app look broken. Capturing `PHAsset` in a `@Sendable` closure breaks Swift 6
compilation. Behaviour of very large single requests is unknown until the spike is done.

## Implementation hints

- **Start from** the existing `AssetDeletionService` protocol, `DeletionOutcome` entity and `PhotoKitAssetDeletionService`
  placeholder (SPS-2); reshape `DeletionOutcome` into the result above rather than adding a second type.
- Verify `PHPhotoLibrary.authorizationStatus(for: .readWrite)` is `.authorized` or `.limited`.
- Map errors: `userCancelled` → `cancelled = true`; `accessUserDenied`/`accessRestricted` → `.permissionDenied`; anything else → `.unknown(message)`.
- After success, re-fetch the IDs; any still present → `failed[.notDeleted]`.
- Tests via a protocol-wrapped `PhotoLibraryPerforming` mock: success, user cancel, partial non-deletable, permission revoked.

## Implementation notes

- `DeletionOutcome` was reshaped into `DeletionResult` (struct: `deleted`, `failed`, `cancelled`) plus `DeletionError`
  (`unavailable`, `notDeletable`, `permissionDenied`, `notDeleted`, `unknown(String)`). Helpers:
  `DeletionResult.permissionDenied(for:)` and `isPermissionDenied`.
- `AssetDeletionService.delete(assetIDs:)` is now `async` and **non-throwing**: every outcome is typed. "Maps to
  `.cancelledByUser`" became `cancelled == true`; "`.permissionDenied` is returned" became every requested ID in `failed`
  with `.permissionDenied` (no PhotoKit call, no alert).
- On a user cancel, `deleted` is empty and `failed` holds only what was known before the alert (`unavailable`,
  `notDeletable`), so the UI can stay silent and ignore `failed`.
- Input IDs are de-duplicated in first-seen order. An empty request, or one where nothing is deletable, shows no system alert.
- `deleted` holds only IDs from a request PhotoKit completed **and** that a re-fetch afterwards no longer finds; IDs still
  present become `.notDeleted`. A failed request deletes nothing (its IDs all get the mapped error, `unknown` carries
  `"<domain> <code>"`, not a user-facing message).
- PhotoKit sits behind the internal `PhotoLibraryPerforming` protocol (`PhotoKitLibraryPerformer` in production): only ID
  strings cross it, and the `performChanges` block re-fetches the assets itself. Fetches include hidden and burst assets.
- Chunked fallback: `PhotoKitAssetDeletionService(chunksAfterFailure:)`, **off** in `AppContainer`. When on, a single
  request that failed for a reason other than cancel or lost access is retried in chunks of 500 (one alert each); a cancel
  stops the remaining chunks and keeps what earlier chunks deleted (`cancelled == true` with a non-empty `deleted`).
- Device-only checks still open: the 2,000-asset spike (one request vs. the chunk flag); Limited access (fetch by ID
  should return only accessible assets → `unavailable`); shared-album assets report `canPerform(.delete) == false`; the
  re-fetch right after `performChanges` no longer sees deleted assets; the zero-network QA over a deletion
  ([docs/qa/zero-network.md](../qa/zero-network.md)), which needs a Debug hook until SPS-25 adds the UI.
- Unverified on Windows: `Packages/Data` (incl. the new tests in `PhotoKitAssetDeletionServiceTests` and
  `PhotoKitAssetDeletionFallbackTests`), the app build and SwiftLint run only in macOS CI.
