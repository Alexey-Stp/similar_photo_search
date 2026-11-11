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
- From SPS-24: `delete(assetIDs:)` is non-throwing and returns `DeletionResult { deleted, failed: [String: DeletionError], cancelled }`. Cancel → `cancelled == true`, possibly partial: with one request (default) `deleted` is empty and `failed` holds only pre-alert `unavailable`/`notDeletable`, but with the chunked fallback earlier chunks' deletions and failures are kept, so still purge `deleted` and return to the review sheet with the rest; lost access → `isPermissionDenied`; partial reasons per ID: `notDeletable` (shared album), `unavailable`, `notDeleted`, `unknown`. Purge and `excludeDeleted` only `deleted`, never the requested IDs.

## Implementation notes

- **Where things live.** `DeletionViewModel` (Presentation/Deletion, `@Observable @MainActor`, one per sheet,
  `ViewModelFactory.makeDeletionViewModel(request:)` in `AppContainer`). Deps differ from the hint: `AssetDeletionService`,
  `FeaturePrintCache`, **`ScanViewModel`** (its `selection` is the `SelectionStore`; it owns the row order and the
  coordinator), `ThumbnailLoading`, `PhotosAppOpening`, `BackgroundTaskRunning`. No `ClusterRepository`: as SPS-14 says,
  the next scan replaces the stored clusters. Views: `DeletionSheet` (host, `.interactiveDismissDisabled` while
  deleting) + `DeletionFlowView`, `DeletionReviewView`, `DeletionProgressView`, `DeletionResultView`, `DeletionFailedView`.
  `ClusterListScreen` presents it with `.sheet(item:)` on `ClusterListViewModel.deletionRequest` and clears it on close.
- **State.** `review → deleting → success(DeletionOutcome) | partial(DeletionOutcome) | failed(String)`. Cancel →
  `review` with the IDs that were not deleted (all of them with one request; with the chunked fallback earlier chunks'
  deletions are processed first). `failed` only for lost access (`isPermissionDenied` with nothing deleted); a result
  where nothing was deleted for other reasons is a `partial` ("Deleted 0 of 5…") that lists the reasons. An ID that is
  in neither `deleted` nor `failed` without a cancel counts as `.notDeleted`. The partial sentence names the reason in
  parentheses only when all failures share one; the failed photos are listed with thumbnail and reason.
- **Post-deletion sync** is `ScanViewModel.deletionFinished(deleted:)` (async; the flow calls `deletionStarted()`
  first): `SelectionStore.removeDeleted(_:)` → row order `rename`/`remove` → `clusterRevision += 1` →
  `await coordinator.excludeDeleted`. Then `FeaturePrintCache.purge(assetIDs:)`; a purge error is ignored (SPS-10
  reconciles). Only `result.deleted` is ever processed.
- **Recomputed groups** (`ClusterSelection.removingMembers(_:)`, Domain, pure): survivors in order, ranking filtered,
  distance/exact flag kept. A surviving keeper stays; otherwise the best-ranked survivor becomes the keeper (kept,
  `needsReview`), none if nothing is ranked. **The ID stays unless the naming photo was deleted; then it becomes the
  newest survivor** — the same ID a running scan gives the shrunk cluster (`ScanRun.withoutExcludedMembers` uses the
  default ID), so a re-publish lands on the same row. The row keeps its position (`ClusterRowOrder.rename`,
  `SelectionStore.clusterIDs` replaced in place). Fewer than 2 survivors → removed, except a single
  survivor that is still selected (the user deleted the whole group and that photo failed): it stays as a one-photo
  group, selected, so it can be retried.
- **Stale publishes.** `ScanViewModel` remembers the session's deleted IDs (`deletedAssetIDs`, set before the first
  suspension of `deletionFinished`) and reconciles every `.added` update with `removingMembers` before `upsert`, so a
  group the scan published before `excludeDeleted` reached it can't bring deleted photos back or recreate an old row.
- **Decision: survivors keep the user's choice.** Selected survivors (photos that failed to delete) stay selected, a
  chosen Best that survived stays Best, delete-all stays confirmed while every survivor is selected. The choice is
  recorded as an override for the **new** member set, so a rescan that publishes the same survivors restores it
  (`upsert` would otherwise drop it). If the deleted photo was the chosen Best, the group falls back to its new suggestion.
- **No rescan for our own change.** The deletion fires a library change, which made Home start a silent rescan.
  `HomeViewModel.libraryDidChange` now ignores changes while `ScanViewModel.isOwnDeletionInProgress`: during the
  deletion and for `ownChangeQuietPeriod` (5 s = 1 s debounce + slack) after it. A change from elsewhere in that window is
  picked up by the next change or launch. The list's missing-photo check still runs (harmless: the IDs left the groups).
- **Background.** The flow holds a `beginBackgroundTask("SimilarPhotos.delete")` from confirm until the state is set, so
  the bookkeeping finishes if the user leaves right after answering the alert. The view model is the source of truth;
  the sheet stays up across scene changes.
- **Open Photos:** `PhotosAppOpening` (Presentation) → `UIKitPhotosAppOpener` (app target, `photos-redirect://`,
  `canOpenURL`); `LSApplicationQueriesSchemes = [photos-redirect]` added to Info.plist. Shown only when something was
  deleted and the system can open it.
- **Not done: the optional App Store review prompt.** `requestReview` is StoreKit UI that talks to the App Store on the
  app's behalf, which the zero-network checklist can't tell apart from the app's own traffic; left out deliberately.
- **Strings:** `deletion.*` (29 keys). `docs/qa/zero-network.md` scope note updated: deletion now runs from the UI.
- **Verified on Windows:** Domain tests (226, incl. 9 `ClusterSelectionRemovalTests`, `-warnings-as-errors`); the three
  `scripts/check-*.sh`. The view-model layer compiled in a scratch package (SwiftUI/CoreGraphics stubbed,
  `-warnings-as-errors`), where `DeletionViewModelTests` (10), `SelectionStoreDeletionTests` (8), `ScanDeletionTests` (5),
  `ClusterRowOrderTests` (incl. rename) and all other suites passed; only the existing string-catalog tests failed there,
  as in SPS-18/21/22. **Not run (need macOS CI):** the real Presentation build and tests, the views and previews, the app
  build (`UIKitPhotosAppOpener`, `AppContainer`), `check-info-plist.sh`, SwiftLint.
- **Manual QA still open (device):** review sheet with 1 and ~2,000 photos (strip scrolls, memory flat); system alert →
  Don't Allow returns to the review unchanged; success text, size and "Open Photos" (hidden if `photos-redirect://`
  stops working); a shared-album photo gives "Deleted N of M … (shared album)" and stays selected in its group; deleting
  during a scan: the scan keeps going, groups shrink in place, no second scan starts afterwards; go to the Home screen
  while the alert is up and come back (alert and progress still there, result correct); VoiceOver, AX5, Dark Mode; the
  zero-network checklist over the whole flow.
