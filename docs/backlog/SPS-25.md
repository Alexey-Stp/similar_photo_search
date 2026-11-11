# SPS-25 — Deletion confirmation flow, results and post-deletion sync

**Type:** User story · **Epic:** SPS-23 · **Depends on:** SPS-18, SPS-21, SPS-24

## User story

As a user, I want to see a clear summary before deleting and an accurate result afterwards, so that I trust the app and know
I can recover photos from Recently Deleted.

## Acceptance criteria

- **Given** N > 0 photos are selected, **when** the user taps "Delete N photos", **then** a review sheet shows the count,
  estimated size, number of groups, a thumbnail strip and the note: "Deleted photos move to Recently Deleted and can be recovered for 30 days."
- **When** the user confirms, **then** `AssetDeletionService` is called and a non-dismissible progress state is shown until the system alert resolves.
- **Given** success, **then** a success screen appears ("Deleted N photos (~X MB). The space is freed when Recently Deleted is emptied.") with a shortcut that opens the Photos
  app (`photos-redirect://`, best effort; hidden if it can't be opened).
- **Given** a user cancel, **then** the user returns silently to the review sheet with the selection unchanged.
- **Given** a partial failure, **then** the screen says "Deleted 40 of 45. 5 couldn't be deleted (shared album)", and the failed items stay visible and selectable.
- Post-deletion: `FeaturePrintCache.purge(ids:)` for deleted IDs. Clusters are recomputed locally; clusters left with fewer
  than 2 members are removed; no re-scan. Selection is cleared for the deleted IDs.
- **Given** a scan is still running, **when** deletion succeeds, **then** the deleted IDs go to
  `AnalysisCoordinator.excludeDeleted(_:)`, the scan continues, and they are never analysed.
- **Given** the app goes to the background while the system alert is shown, **then** the state recovers correctly on return.
- Optional: request an App Store review (`requestReview`) after the first successful deletion of 20 or more photos, at most once per version.
- The zero-network manual QA ([docs/qa/zero-network.md](../qa/zero-network.md)) passes over the whole flow.

## Technical notes

`DeletionViewModel` with `enum State { review, deleting, success(Summary), partial(Summary), failed(String) }`, `.sheet` and
`.interactiveDismissDisabled()` while deleting. `@Environment(\.requestReview)`. `photos-redirect://` must not trip the
`no_remote_url_literals` lint rule (it only matches http/ws/ftp) and needs `LSApplicationQueriesSchemes` for `canOpenURL`.

## Risks

The cache and library can get out of sync if the app is killed between deletion and purge; the SPS-10 change tracker
reconciles deleted IDs on the next launch. `photos-redirect://` is undocumented and may stop working.

## Implementation hints

- `DeletionViewModel` (`@Observable @MainActor`) deps: `AssetDeletionService`, `FeaturePrintCache`, `ClusterRepository`, `SelectionStore`.
- Views: `DeletionReviewSheet` (count, `ByteCountFormatter` size, groups, thumbnail strip, Recently Deleted note, destructive
  confirm), `DeletionProgressView` (`.interactiveDismissDisabled(true)`), `DeletionResultView` (success/partial, failed items with reasons, "Open Photos").
- Store the last version that asked for a review in `@AppStorage` (UserDefaults is already declared in the privacy manifest).
- Unit tests for state transitions and cache/cluster cleanup with mocks.
- From SPS-13: the method is `FeaturePrintCache.purge(assetIDs:)`.
- From SPS-18: the review sheet can use `selectionStore.summary` (count + estimated bytes, `.text`). Recomputed clusters with fewer members are new member sets, so `upsert` drops their overrides and applies the new suggestion: decide whether surviving members should keep the user's choice. The `.cancelledByUser` path must leave the store untouched.
- From SPS-14: after a successful deletion call `ScanViewModel.photosDeleted(_:)` (forwards to `ScanCoordinating.excludeDeleted`); it does not touch the groups already shown. `FileClusterRepository` needs no cleanup: the next scan sees the shrunk sessions through their fingerprints and replaces or removes their stored clusters.
- From SPS-21: the bottom bar's "Delete N photos (X MB)" button (`SelectionSummaryBar(store:onDelete:)`) sets `ClusterListViewModel.deletionRequest` (selected IDs in list order) and presents nothing; attach the review sheet to it (`.sheet(item:)`) and clear it when done. Removed groups disappear from the list by themselves (`rows` skips IDs missing from the store); call `ScanViewModel` paths, not `SelectionStore.upsert`, if recomputed groups must keep their row (`ClusterRowOrder`).
- From SPS-22: the comparison (full-screen cover over the list, no delete button) writes straight into `SelectionStore`, including a user-chosen Best (`ClusterSelectionState.chosenKeeperID`; `keeperID` returns it before the suggestion's). It is stored with the override, so recomputed groups with new members drop it too; if a deleted photo was the chosen Best, the surviving group falls back to its new suggestion.
- From SPS-24: `delete(assetIDs:)` is non-throwing and returns `DeletionResult { deleted, failed: [String: DeletionError], cancelled }`. Cancel → `cancelled == true` (ignore `failed`; it only holds pre-alert `unavailable`/`notDeletable`); lost access → `isPermissionDenied`; partial reasons per ID: `notDeletable` (shared album), `unavailable`, `notDeleted`, `unknown`. Purge and `excludeDeleted` only `deleted`, never the requested IDs.
