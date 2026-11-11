# SPS-22 — Photo comparison screen (side-by-side and swipe)

**Type:** User story · **Epic:** SPS-19 · **Depends on:** SPS-18, SPS-21

## User story

As a user, I want to compare similar photos at full size, zoom in on details and see why one was picked as best, so that I'm confident about what I delete.

## Acceptance criteria

- Full-screen pager across the cluster members, with a filmstrip at the bottom. On iPad or landscape, a two-up side-by-side mode is available.
- Pinch-to-zoom and double-tap zoom. In side-by-side mode, zoom and pan are **synchronized** across both images.
- Images load at screen resolution (never `PHImageManager.maximumSize`), `isNetworkAccessAllowed = false`. **Given** a
  full-size image is not on the device, **then** the high-quality local thumbnail is shown with an "Original in iCloud" label.
- An info panel shows date, resolution, file size (if available), Favorite or Edited badges, and the quality reasons ("Sharpest", "Eyes open").
- Actions: "Keep this one" (selects all others), toggle delete, and "Mark as Best" (manual override).
- Live Photo badge. Playback through `PHLivePhotoView` is a nice-to-have behind a flag.
- Dismiss with a swipe down; selection changes apply immediately to `SelectionStore`.

## Technical notes

`TabView(.page)` for the pager, `MagnifyGesture` combined with `DragGesture`, a shared `ZoomState` object for synchronized
zoom. `.presentationBackground(.black)`, `.statusBarHidden()`.

## Risks

Full-resolution 48 MP images (about 190 MB decoded) crash the app if requested at original size: always cap at screen
pixels. Synchronized gestures are fiddly; test with VoiceOver and Reduce Motion.

## Implementation hints

- Inputs: cluster, ranked members with reasons, `SelectionStore`, an image loader that loads at a given size (screen size × displayScale).
- Filmstrip with `ScrollViewReader` keeping the current item visible.
- `ZoomableImage`: `MagnifyGesture` + `DragGesture` + double-tap 1x/2.5x, clamped offsets.
- Side-by-side when `horizontalSizeClass == .regular` or landscape; two `ZoomableImage`s bound to one `@Observable ZoomState`.
- Keep only current ±1 full-size images in memory.
- Accessibility: zoom via `accessibilityZoomAction`, labels on all buttons. Previews.
- From SPS-18: `SelectionStore` has no "Mark as Best" or "Keep this one" yet; add them there (keeping the at-least-one-kept invariant and override recording) instead of toggling member by member. Reasons come from `ClusterSelection.ranking`.
- From SPS-21: open from `HomeRoute.comparison(clusterID:)` (`HomeViewModel.compare(clusterID:)`, called by the card header and the VoiceOver action "Compare"); replace the interim `ClusterComparisonScreen` (ClusterList/). `ClusterListViewModel` has the members' dates and missing photos (`card(for:)`), `toggle(_:in:)` with the delete-all confirmation, and the thumbnail loader (`ThumbnailLoading`, for the filmstrip and the "high-quality local thumbnail" fallback).

## Implementation notes

- **Presentation.** `PhotoComparisonViewModel` (Comparison/, `@Observable @MainActor`, `+Photos.swift` for details and
  actions) is built per presentation by `ViewModelFactory.makePhotoComparisonViewModel(clusterID:)` (AppContainer) over
  the session's `ClusterListViewModel` (store, thumbnails, library, sizes). Views: `PhotoComparisonScreen` (+ private
  top bar and pager page), `ComparisonPane` (loads one screen image), `ZoomableImage`, `ComparisonFilmstrip`,
  `ComparisonInfoPanel`, `PhotoComparisonHost` (creates the view model once). The interim `ClusterComparisonScreen` is gone.
- **Presentation is full screen, not a push.** `HomeRoute.comparison` was removed; `HomeViewModel.compare(clusterID:)`
  sets `comparison: ComparisonRequest?`, which `HomeDashboard` presents with `.fullScreenCover(item:)` (a navigation
  push can't be full screen with a black background). Swipe down dismisses (custom drag, only when not zoomed and
  mostly vertical; > 120 pt or a fast flick), as do Close and the VoiceOver escape gesture.
- **What is shown.** The pager starts on the group's Best. Side by side (offered when `horizontalSizeClass == .regular`
  or `verticalSizeClass == .compact`, toggle in the top bar, on by default): left = current photo, right = the Best, or
  the next photo when the left one is the Best. Tapping a pane focuses it; the info panel and the filmstrip act on the
  focused pane, and picking the other pane's photo swaps them. Photos are read live from the store by ID, so a rescan
  updates the screen; a removed group shows "This group is no longer available".
- **Zoom.** `ZoomState` (pure, tested): 1…4×, double tap 1× ↔ 2.5× around the tap, VoiceOver
  `accessibilityZoomAction` steps ×1.5, offsets clamped to the fitted image. Side by side, both panes share
  `sharedZoom`, so zoom and pan are synchronized live (gestures write the shared state directly, not `@GestureState`).
  The pager's current page uses `pagerZoom`, reset on every page change; the drag is disabled at 1× so paging and
  swipe-down keep working.
- **Images.** New Presentation protocol `ScreenImageLoading` → `ScreenImage` (`Thumbnail` + `isOriginalInCloud`).
  Data: `PhotoKitScreenImageLoader` over two `PhotoKitScreenImageRequester`s (`PHImageManager.default()`, aspect fit,
  `isNetworkAccessAllowed = false`): `.original` = `.highQualityFormat` + `.exact`; only when that answer says "in cloud"
  does it ask `.localPreview` (`.opportunistic`) and return it flagged → "Original in iCloud" label. Sizes are pane
  size × display scale (`ComparisonLayout.pixelSize`), capped at 4,096 px per side in both layers, so
  `PHImageManagerMaximumSize` can never be requested. Task cancellation cancels the PhotoKit request
  (`CancellableImageRequest`, the thumbnail loader's former private `PendingThumbnail`).
- **Memory.** Only the current page and its neighbours hold a screen image (`shouldLoadFullImage`), side by side only
  the two shown photos; other pages release theirs when they leave the window.
- **Selection.** `SelectionStore.markAsBest(_:in:)` and `keepOnly(_:in:excluding:)` (in `SelectionStore+Comparison`).
  The user's Best is `ClusterSelectionState.chosenKeeperID` (`keeperID` returns it first, so card and filmstrip badges
  follow it); it is part of the override (restored on a rescan with the same members, dropped otherwise, cleared by
  Smart Select All). Mark as Best also keeps that photo. **Keep This One also marks the photo Best** (so the badge never
  sits on a photo selected for deletion) and, being an explicit action, selects favorites too; photos missing from the
  library are left out. Toggling the last kept photo asks with the same "Delete every photo of this group?" dialog
  (comparison's own `isConfirmingDeleteAll`, so the list's dialog under the cover never fires).
  `reclaimableBytes` now uses `suggestion.keeperID`, so the size sort doesn't move when the user picks another Best.
- **Info panel.** Date, "4032 × 3024 · 12.2 MP", file size (`AssetSizeEstimator`, all resources) or "Size unavailable",
  badges Best / Will Be Deleted or Kept / Favorite / Edited / Live, and the ranking's reasons ("Favorite" is a badge,
  so it is not repeated). Stored groups at launch have no ranking, so no reasons until the scan re-publishes them.
  Edited comes from the new Domain protocol `PhotoEditStatusProviding` (`MockPhotoEditStatusProvider`), implemented by
  `PhotoKitEditStatusProvider` (actor over the existing `AssetEditInspecting`, resource metadata only).
- **Not done:** Live Photo playback (`PHLivePhotoView`, nice-to-have) — only the badge.
- **Verified on Windows:** Domain tests (212, `-warnings-as-errors`); `check-domain-imports.sh`,
  `check-concrete-construction.sh`, `check-privacy-manifest.sh`. The view-model layer compiled in a scratch package
  (SwiftUI/CoreGraphics stubbed), where `SelectionStoreComparisonTests`, `ZoomStateTests`, `ComparisonLayoutTests`,
  `PhotoComparisonViewModelTests`, `HomeViewModelTests`, `ClusterListViewModelTests`, `ScanViewModelTests` passed; only
  the existing string-catalog tests failed there, as in SPS-18/21. **Not run (need macOS CI):** the real Presentation
  build and tests, the views and previews, `Packages/Data` (`PhotoKitScreenImageLoaderTests`,
  `PhotoKitEditStatusProviderTests`), the app build, SwiftLint.
- **Manual QA still open (device):** a 48 MP photo opens without a memory spike (Instruments: only ±1 screen images
  alive while paging through a 30-photo group); pinch/double-tap/pan feel and the synchronized zoom on iPad and iPhone
  landscape; paging and swipe-down are not stolen by the zoom gestures at 1×; an iCloud-only original shows the local
  preview with "Original in iCloud" in Airplane Mode and nothing is downloaded; VoiceOver (labels, zoom action, escape,
  focus action), Reduce Motion, AX5 Dynamic Type; badges Edited/Live/Favorite on real photos.
