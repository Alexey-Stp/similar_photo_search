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
