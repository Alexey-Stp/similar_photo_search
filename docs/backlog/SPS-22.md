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
