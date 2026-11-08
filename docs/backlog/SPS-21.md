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
