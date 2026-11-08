# SPS-24 — `AssetDeletionService` via PhotoKit change requests

**Type:** Technical task · **Epic:** SPS-23 · **Depends on:** SPS-2

## Description

A service that deletes assets by local identifier and maps every outcome to a typed result.

## Acceptance criteria

- Re-fetch the assets with `PHAsset.fetchAssets(withLocalIdentifiers:options:)` right before deletion; missing IDs are reported as `alreadyDeleted`, not as an error.
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
