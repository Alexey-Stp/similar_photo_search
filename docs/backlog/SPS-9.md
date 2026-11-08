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

- Domain protocol `ImageLoading` (no `CGImage` in Domain: keep the image type in Data, or pass an opaque `Sendable` wrapper).
- `func loadImage(assetID: String, targetSize: CGSize) async throws -> LoadedImage` with
  `struct LoadedImage: @unchecked Sendable { let cgImage: CGImage; let orientation: CGImagePropertyOrientation }` and
  errors `ImageLoadError.notFound, .iCloudOnly, .decodeFailed, .cancelled`.
- `func loadBatch(_ ids: [String], targetSize: CGSize, maxConcurrent: Int) -> AsyncStream<(id: String, result: Result<LoadedImage, ImageLoadError>)>`
  using a `TaskGroup` that adds the next child only when one finishes.
- `PHAsset.fetchAssets(withLocalIdentifiers:options:)`; inspect `PHImageResultIsInCloudKey`, `PHImageCancelledKey`, `PHImageErrorKey`.
- Convert `UIImage.imageOrientation` to `CGImagePropertyOrientation`.
- Tests: mock `PHImageManager` behind a protocol; verify the concurrency cap and single-resume behaviour.
