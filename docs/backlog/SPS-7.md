# SPS-7 — `PhotoLibraryRepository` with scope filters

**Type:** Technical task · **Epic:** SPS-6 · **Depends on:** SPS-2

## Description

Wrap `PHAsset` fetching behind `PhotoLibraryRepository`. Return lightweight `PhotoAsset` domain models, or an index-based
lazy sequence so that 100k objects are not materialized at once. Filters: images only, exclude screenshots (optional),
exclude hidden, specific album(s), date range.

## Acceptance criteria

- Fetch uses `PHFetchOptions` with predicate `mediaType == %d` (`PHAssetMediaType.image`) and sort `creationDate` descending.
- The order is a hard contract: assets are delivered strictly by `creationDate` descending (ties broken by `localIdentifier`),
  because session splitting (SPS-26) and live results depend on it.
- Option to exclude screenshots through `!(mediaSubtypes & %d)` with `PHAssetMediaSubtype.photoScreenshot`.
- Hidden assets are excluded (`includeHiddenAssets = false`, the default; assert it in a test).
- Live Photos are included as still images. Bursts: only the representative by default (`includeAllBurstAssets = false`).
- Album scope: `PHAssetCollection.fetchAssetCollections(with: .album/.smartAlbum, ...)`, then `PHAsset.fetchAssets(in:options:)`.
- Edge case: an empty library returns an empty result and the UI shows the "No photos" state.
- Edge case: assets with `creationDate == nil` sort last and are still processed. When the scope has a date range, they
  are outside it and are neither returned nor counted (`ScanScope.dateRange`).
- Edge case: under Limited access, only the accessible assets are returned, and the count matches for the whole library or
  a single album. For overlapping albums `assetCount` stays an upper bound (see the notes).
- Performance: enumerating 50k assets into identifiers takes under 2 s on an iPhone 12.

## Risks

Turning the whole `PHFetchResult` into an array causes memory spikes and UI hangs. `PHAsset` is not `Sendable`.

## Implementation notes

- API: `assetCount(scope:)`, `assetPages(scope:pageSize:)` and `albums()`. The order contract is `PhotoAsset.libraryOrder` (Domain).
- PhotoKit cannot sort by `localIdentifier`, so `OrderedAssetPager` (Data) restores the contract: the run of photos sharing a
  page's last timestamp is held back to the next page, and each page is sorted. A whole equal-timestamp run stays on one
  page, so a page can be much larger than `pageSize` (for example an import of thousands of photos with one date).
- Photos without a date are collected while paging and delivered after all dated photos, sorted by id. With a date range
  in the scope they are filtered out by the fetch, so SPS-26 can only count "skipped (no date)" for scans without a date
  range; counting them there too would need a change to the `ScanScope` filtering contract.
- Several selected albums are merged by date and de-duplicated by id. `assetCount` for overlapping albums is an upper bound.
- Pages are produced on demand (`AsyncThrowingStream(unfolding:)`), so the stream never runs ahead of its consumer.
- `PhotoAsset` gained `modificationDate` (cache key, SPS-13) and `burstIdentifier` (SPS-16, SPS-26).
- The limited-access banner still uses `PhotoPermissionService.accessiblePhotoCount()`; switching it to the repository count is left to SPS-20.
- The 50k performance test (`PhotoLibraryPerformanceTests`) is device-only: set `RUN_DEVICE_PERFORMANCE_TESTS=1` in the scheme.
