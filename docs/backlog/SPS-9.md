# SPS-9 — Memory-safe batched image loading pipeline

**Type:** Technical task · **Epic:** SPS-6 · **Depends on:** SPS-7

## Description

Build an `ImageLoader` that turns `PhotoAsset` IDs into downscaled `CGImage`s for analysis, with bounded concurrency, no
network, in batches, so memory stays flat no matter how big the library is.

## Acceptance criteria

- Requests use `PHImageManager.requestImage(for:targetSize:contentMode:options:)` with `targetSize` 512×512 px
  (configurable), `.aspectFit`, `deliveryMode = .highQualityFormat` (one callback), `resizeMode = .fast`,
  `isNetworkAccessAllowed = false` and `version = .current`.
- **Given** an asset whose original exists only in iCloud, **when** loading fails (`info[PHImageResultIsInCloudKey] == true`
  or a nil image), **then** the asset is marked `skipped(.iCloudOnly)`, the batch continues, and the count is shown in the scan summary.
- **Given** a corrupt or undecodable asset, **then** it is marked `skipped(.decodeFailed)` without crashing.
- Concurrency is capped at `min(4, activeProcessorCount)` in-flight requests.
- Peak memory stays at or below 250 MB during a 10k-asset run (Instruments Allocations, iPhone 12).
- Cancellation: cancelling the parent `Task` calls `PHImageManager.cancelImageRequest(_:)` for pending requests within 200 ms.

## Technical notes

`PHImageManager.default()` for analysis; `PHCachingImageManager` only for UI thumbnails (SPS-21), because pre-caching for
analysis wastes memory. Bridge the callback API with `withCheckedThrowingContinuation` + `withTaskCancellationHandler`. Wrap
each image in `autoreleasepool {}`. Hand `CGImage` downstream, not `UIImage`, and keep `CGImagePropertyOrientation`.

## Risks

Resuming the continuation twice crashes; never resuming hangs the task. PhotoKit callbacks can fire twice with
`.opportunistic`. Holding `UIImage`s in arrays leads to OOM.

## Implementation hints

- Domain never sees an image. `ImageLoading` and `LoadedImage` (below) are declared in **Data**, next to their only
  consumers: the Vision `FeaturePrintService` and `QualityScorer` implementations, which already take asset IDs in their
  Domain protocols and load the image internally. Domain gets the outcome as values (a `FeaturePrint`, a score, a skip
  reason), so no Domain protocol names `LoadedImage` and the Data → Domain dependency direction is unchanged.
- `func loadImage(assetID: String, targetSize: CGSize) async throws -> LoadedImage` with
  `struct LoadedImage: @unchecked Sendable { let cgImage: CGImage; let orientation: CGImagePropertyOrientation }` and
  errors `ImageLoadError.notFound, .iCloudOnly, .decodeFailed, .cancelled`.
- `func loadBatch(_ ids: [String], targetSize: CGSize, maxConcurrent: Int) -> AsyncStream<(id: String, result: Result<LoadedImage, ImageLoadError>)>`
  using a `TaskGroup` that adds the next child only when one finishes.
- `PHAsset.fetchAssets(withLocalIdentifiers:options:)`; inspect `PHImageResultIsInCloudKey`, `PHImageCancelledKey`, `PHImageErrorKey`.
- Convert `UIImage.imageOrientation` to `CGImagePropertyOrientation`.
- Tests: mock `PHImageManager` behind a protocol; verify the concurrency cap and single-resume behaviour.

## Implementation notes

- Types live in Data (`ImageLoading/`): `ImageLoading`, `LoadedImage`, `ImageLoadError`, `ImageLoadOutcome`,
  `ImageLoadingDefaults` (512 px, `min(4, activeProcessorCount)`). Domain only gained `SkipReason`
  (`iCloudOnly`, `decodeFailed`, `notFound`); `ImageLoadError.skipReason` maps to it (`cancelled` is not a skip).
- PhotoKit sits behind `ImageRequesting`; `PhotoKitImageRequester` is the only code that touches `PHAsset` and
  `UIImage`/`NSImage` for analysis. The Data package also builds for macOS (`swift test`), where PhotoKit returns `NSImage`
  already upright (orientation `.up`).
- `.highQualityFormat` means one callback, and it is treated as final: a degraded or missing image is a skip
  (`iCloudOnly` if PhotoKit says the data is in iCloud, otherwise `decodeFailed`), never something to wait for.
  So "nil image" maps to `iCloudOnly` only together with `PHImageResultIsInCloudKey`. Duplicate callbacks are ignored.
- **Deviation from the hint:** `loadBatch` is not a `TaskGroup` feeding an `AsyncStream`. That would run ahead of a slow
  consumer (Vision) and buffer images without limit. A small window (`ImageBatchWindow`) keeps in-flight loads plus
  undelivered outcomes ≤ `maxConcurrent` and starts the next load only when the consumer takes one. Outcomes arrive in
  completion order. `maxConcurrent` below 1 is treated as 1 (like `pageSize`); to pause (critical thermal state), the
  caller must not start a batch.
- Cancellation: cancelling the consuming task (or the `loadImage` caller), or dropping the stream early (`break`, a
  thrown error), calls `cancelImageRequest` for every pending request; unit tests assert it happens within 200 ms.
  A stream kept alive in a variable after its loop ends keeps its batch until it is released.
- Not wired into `AppContainer` yet: the first consumers are the Vision services (SPS-12, SPS-17).
- Device-only, still open: the 250 MB peak in Instruments on an iPhone 12, and `ImageLoadingPerformanceTests`
  (10k photos, memory growth < 100 MB) with `RUN_DEVICE_PERFORMANCE_TESTS=1`.
