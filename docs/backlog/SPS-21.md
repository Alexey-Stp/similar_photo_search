# SPS-21 — Cluster list with efficient thumbnail loading

**Type:** User story · **Epic:** SPS-19 · **Depends on:** SPS-18, SPS-20

## User story

As a user, I want to scroll through groups of similar photos with the suggested deletions clearly marked, so that I can review many groups quickly.

## Acceptance criteria

- `List`/`LazyVStack` of cluster cards. Each card shows a horizontal strip of thumbnails, a "Best" badge on the kept photo, a
  checkmark overlay on selected photos, the date and the count.
- Tapping a thumbnail toggles selection (`.sensoryFeedback(.selection, trigger:)`). Tapping the card header opens the comparison view (SPS-22).
- Thumbnails come from `PHCachingImageManager` at `targetSize = displaySize × displayScale`, `deliveryMode = .opportunistic`,
  `isNetworkAccessAllowed = false`. `startCachingImages`/`stopCachingImages` for prefetch windows while scrolling.
- **Given** a thumbnail request is in flight when the cell leaves the screen, **then** it is cancelled.
- **Given** an asset was deleted externally, **then** its cell shows a placeholder and the cluster refreshes (SPS-10 observer).
- Filters: "Needs review", "Exact duplicates"; sort by date or reclaimable size.
- A sticky bottom bar shows "Delete N photos (X MB)" and is disabled when N is 0.
- **Given** a scan is running, **when** new groups arrive (`ClusterUpdate.added`), **then** they are appended at the end
  (newest sessions come first, so new results are older photos). Visible rows don't move; selections and scroll position are kept.
- **Given** groups newer than the first row arrive outside the scan's append order (the SPS-10 live observer found new
  photos), **then** they are inserted above the current rows with the scroll position anchored to the first visible row, so
  nothing on screen moves; the user reaches them by scrolling up. This is the only exception to append-only (SPS-14, CLAUDE.md).
- **Given** a scan is running, **then** the list ends with a footer row "Still scanning… 4,210 of 18,000".
- **Given** a scan is running and the sort is not by date, **then** new groups are inserted at their sorted position only when
  the user is not touching the list (applied on scroll end).
- VoiceOver: each thumbnail reads "Photo 2 of 5, taken 12 May 14:03, selected for deletion, Best shot" with custom actions "Toggle selection" and "Compare".

## Technical notes

A `ThumbnailLoader` actor wraps `PHCachingImageManager`. `AsyncThumbnail` uses `.task(id: assetID)` (auto-cancels). Avoid
`AnyView`. Make cluster rows `Equatable`. Read selection per cell through fine-grained `@Observable` properties.

## Risks

`.opportunistic` calls the handler twice, so the stream must handle both callbacks. Unbounded `startCachingImages` exhausts
memory. Large `@Observable` selection dictionaries invalidate every cell unless reads are scoped per cell.

## Implementation hints

- `ThumbnailLoader.thumbnail(for:size:) -> AsyncStream<UIImage>`: may yield degraded then final; finish on final
  (`PHImageResultIsDegradedKey == false`); cancel the request on termination. `prefetch(ids:size:)` / `stopPrefetch(ids:size:)`.
- `ClusterCardView` (Equatable): header (date, count, "Review recommended" chip), thumbnail strip, overlays (Best badge, checkmark, dimming).
- `ClusterListViewModel`: filter/sort, append-only live updates with stable IDs, prefetch rows ±10 on `.onAppear`.
- Accessibility: `accessibilityElement(children: .ignore)` + label + `accessibilityActions` per thumbnail.
- Previews with a mock loader returning SF Symbol images.
- From SPS-18: nobody runs Smart Selection yet. On each `ClusterUpdate`, rank with `SmartSelectionUseCase.suggest(for:signals:)` and `selectionStore.upsert(_:)` the result (removed clusters: `remove(clusterIDs:)`). Cells read `store.state(for: clusterID)`, never the store's totals; a `.needsConfirmation` toggle shows a confirmation, then `confirmDeleteAll(_:)`. `SelectionSummaryBar` already has Smart Select All / Deselect All and the summary text; add the delete button to it. Badge strings: `selection.keepBest`, `selection.reviewRecommended`.
- From SPS-14 (replaces the SPS-18 line above): the coordinator already runs Smart Selection; `ClusterUpdate.added` carries `[ClusterSelection]` and `ScanViewModel` already upserts/removes them in `SelectionStore` (`clusterIDs` is the append order). Every scan re-publishes all current groups, reused ones too, under the same IDs.
- From SPS-20: Home pushes `HomeRoute.clusters` onto its `NavigationStack`; the destination is the interim `ClusterListScreen` (Presentation/Home), which already pins `ScanProgressBar` at the top while a scan runs, shows `SelectionSummaryBar` and counts itself as a scan screen (`scanScreenAppeared/Disappeared`, now counted). Replace its rows with the cards, keep those three. At launch, stored groups arrive without a suggestion (`ClusterSelection(unsuggested:)`: no keeper, nothing selected) and the silent rescan replaces them in place.

## Implementation notes

- **Where things live.** `ClusterListViewModel` (Presentation/ClusterList, one per app session,
  `factory.clusterListViewModel`, built in `AppContainer`) owns filter, sort, per-photo dates, missing photos,
  reclaimable sizes, the prefetch window and the selection actions. Views: `ClusterListScreen` (Home/, replaces the
  interim rows; keeps `ScanProgressBar`, `SelectionSummaryBar` and the scan-screen counting), `ClusterCardView`
  (`Equatable`, `.equatable()`), `AsyncThumbnail` (`.task(id:)`), `ClusterCardModel` (value per card, VoiceOver text).
- **Row order is `ClusterRowOrder`, owned by `ScanViewModel.rowOrder`** (not `SelectionStore.clusterIDs`, which
  stays append-only). Rule: within one scan, a group new to the list that arrives *before* the scan re-published any
  row already shown is newer than every row (every scan re-publishes all groups newest first), so it is inserted on
  top, in arrival order; every other new group is appended. No dates are needed for this. Stored groups at launch go
  through `ScanViewModel.showStoredResults(_:)` (Home calls it instead of `selection.upsert`).
  `ScanViewModel.clusterRevision` goes up on every added/replaced/removed batch; the screen calls
  `clustersChanged()` on it. `rows` also appends store IDs that reached the store another way (SPS-25 removals are
  filtered out automatically).
- **Scroll anchoring** uses `ScrollView` + `LazyVStack` + `.scrollPosition(id:anchor: .top)` (iOS 17), pinned to the
  first row as soon as one exists, so rows inserted above don't push the visible rows down. **Device QA still open.**
- **Size sort** is a frozen order (`sizeOrder`), recomputed when the sort switches, when sizes or groups arrive and the
  user is not touching the list, and when the interaction ends. Groups that arrive while scrolling stay hidden until
  then. Interaction: `onScrollPhaseChange` on iOS 18; on iOS 17 a simultaneous `DragGesture` (`@GestureState`), which
  can report the end a little early when the scroll view takes over the drag.
- **Reclaimable size of a group** = all members except the keeper (except the largest member when there is no keeper,
  e.g. stored groups at launch). Stable while the user toggles, so rows don't move on a tap. Unavailable sizes count 0.
- **New Domain API:** `PhotoLibraryRepository.assets(withIDs:)` (library order, missing IDs left out, burst members
  included, hidden excluded). Used for card dates and to find photos deleted outside the app: on every
  `LibraryChangeObserving` signal while the list is visible, all shown members are re-checked and missing ones get a
  placeholder and can't be toggled. Home's existing silent rescan then refreshes the groups.
- **Thumbnails.** Protocol `ThumbnailLoading` + `Thumbnail` (CGImage + `Image.Orientation`) live in **Presentation**
  (Domain can't hold images, Data can't see Presentation). Data has `PhotoKitThumbnailLoader` (actor; streams of
  `LoadedImage`, finishes on the non-degraded callback, cancels on `.cancelled` termination; prefetch bounded to 300
  photos per size, least recently prefetched released first) over `PhotoKitThumbnailRequester` (`PHCachingImageManager`,
  `.opportunistic`, `.fast`, `.aspectFill`, `isNetworkAccessAllowed = false`, `allowsCachingHighQualityImages = false`).
  A private `PhotoKitThumbnailBridge` in `AppContainer.swift` maps one to the other. Thumbnails are 88 pt × display
  scale; prefetch covers ±10 rows around the last row that appeared, and everything is released when the list closes.
- **Delete button** ("Delete N photos (X MB)", `SelectionSummaryBar(store:onDelete:)`) only records
  `ClusterListViewModel.deletionRequest` (the selected IDs). Nothing is presented yet: SPS-25 attaches its review sheet.
- **Comparison.** `HomeRoute.comparison(clusterID:)` and `HomeViewModel.compare(clusterID:)`; the destination is an
  interim `ClusterComparisonScreen` (larger thumbnails, same toggle and badges). SPS-22 replaces it.
- **Selecting the last kept photo** sets `pendingDeleteAllClusterID` → confirmation dialog → `confirmDeleteAll()`.
- **Strings:** `clusters.*` (filter, sort, footer, photo label parts, actions, delete-all dialog, `clusters.badge.best`
  "Best"), `compare.title`, `selection.delete*`. `clusters.row.selected` was removed (unused).
- **Verified on Windows:** Domain tests (211, incl. `assetsByIDKeepLibraryOrderAndLeaveOutMissingIDs`),
  `-warnings-as-errors`; `check-domain-imports.sh`, `check-concrete-construction.sh`, `check-privacy-manifest.sh`.
  The view-model layer compiled in a scratch package (SwiftUI, CoreGraphics and `String(localized:)` stubbed), where
  `ClusterRowOrderTests`, `ClusterListViewModelTests`, `ClusterListLoadingTests` (except the VoiceOver-label test),
  `ScanViewModelTests`, `HomeViewModelTests` and `SelectionStoreTests` passed; only the tests that need the string
  catalog failed there, as expected. **Not run (need macOS CI):** the real Presentation build and tests (including
  `theThumbnailLabelReadsPositionDateStatusAndBest`, `theDeleteButtonNamesCountAndSize`), the views and previews,
  `Packages/Data` (`PhotoKitThumbnailLoaderTests`), the app build, SwiftLint.
- **Manual QA still open (device):** no hitches scrolling 1,000 groups (Instruments) and flat memory; a cell scrolled
  away cancels its request; new groups during a scan appear at the end without moving visible rows; a photo added in
  Photos during review inserts its group above without moving the screen; a photo deleted in Photos shows the
  placeholder at once; size sort applies only after scrolling stops; VoiceOver labels and actions; AX5 Dynamic Type
  and Dark Mode; haptic on toggle; iCloud-only photos show a local preview or placeholder, never download (Airplane Mode).
