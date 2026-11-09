# SPS-12 — Feature print extraction via Vision

**Type:** Technical task · **Epic:** SPS-11 · **Depends on:** SPS-9

## Description

`VisionFeaturePrintService` takes a loaded image and returns a feature vector: `[Float]` plus its revision. Raw floats are
stored so distance can be computed without unarchiving `VNFeaturePrintObservation` objects.

## Acceptance criteria

- Uses `VNGenerateImageFeaturePrintRequest` with an explicit `revision`: `VNGenerateImageFeaturePrintRequestRevision2` on
  iOS 17+. The revision is stored alongside each vector.
- Uses `VNImageRequestHandler(cgImage:orientation:options:)`, and orientation is respected.
- The observation's `data` is converted to `[Float]` using `elementCount` and `elementType == .float` (assert the type; throw on `.double` or unknown).
- Distance: Euclidean with Accelerate (`vDSP.distanceSquared`), validated within 1e-4 of
  `VNFeaturePrintObservation.computeDistance(_:to:)` in a unit test.
- **Given** Vision throws (for example image too small), **then** the asset is marked `failed(.vision)` and the pipeline continues.
- Requests and handlers are created per image (never shared across threads), and `autoreleasepool` wraps each call.
- Runs off the main thread; at most 2 concurrent Vision requests by default.

## Technical notes

Vision is synchronous (`perform(_:)`), so call it from a non-main executor. `imageCropAndScaleOption` defaults to
`.scaleFill`; keep it fixed and document it. On iOS 18+ the Swift-native `GenerateImageFeaturePrintRequest` can sit behind the same protocol.
Feature prints and their distances must be checked on a **physical device**.

## Risks

Revisions are not comparable; mixing Revision1 and Revision2 gives meaningless distances. Simulator results differ from
device. A shared `VNRequest` across threads crashes.

## Implementation hints

- **Start from** the existing Domain `FeaturePrint` (`assetID`, `revision`, `vector`, `assetModificationDate`,
  `isComparable(with:)`) and `FeaturePrintService` placeholder (SPS-2) rather than adding a new `FeatureVector` type;
  change the protocol signature to take the loaded image from SPS-9.
- **SPS-9 decided otherwise:** the Domain protocol keeps taking an asset ID. Inject `ImageLoading` (Data) into
  `VisionFeaturePrintService`'s initializer (built in `AppContainer`), load with `ImageLoadingDefaults.targetSize`, and
  report skips as Domain `SkipReason` (`ImageLoadError.skipReason`) instead of a bare `nil`.
- Set `revision = VNGenerateImageFeaturePrintRequestRevision2`; fall back to Revision1 and record it if unavailable.
- Copy `observation.data` into `[Float]` with `withUnsafeBytes` + `bindMemory` and `elementCount`.
- `enum VectorMath { static func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float }` with vDSP and a precondition on
  equal counts. Accelerate is allowed in Domain only for the clustering engine, so put `VectorMath` where SPS-16 can use it.
- Tests: on-device comparison with `computeDistance` for two bundled images (tolerance 1e-4); identical images ≈ 0. Mark
  Neural-Engine tests device-only (same `RUN_DEVICE_PERFORMANCE_TESTS` pattern as SPS-7).

## Implementation notes

- **Contract:** `FeaturePrintService.featurePrint(for: PhotoAsset) async throws -> FeaturePrintOutcome` (Domain). It takes
  the `PhotoAsset`, not just its ID, because the print stores `asset.modificationDate` as part of the cache key. Outcomes:
  `.computed(FeaturePrint)`, `.skipped(SkipReason)` (image not loadable, Vision never ran), `.failed(AnalysisFailure.vision)`.
  It throws **only** `CancellationError`; a Vision error never stops a scan. A print that finished before a
  cancellation is still returned (worth caching); a failure during a cancelled call throws instead of `.failed`.
  The protocol also exposes `revision`, the
  revision new prints get, so the coordinator can query the cache before computing anything.
- `MockFeaturePrintService` now takes `outcomes:` (or `featurePrints:`, all computed) and `revision:`; unknown IDs stay `.skipped(.iCloudOnly)`.
- `VectorMath` (`euclideanDistance`, `euclideanDistanceSquared`, vDSP) lives in `Domain/Clustering/`, the folder
  `check-domain-imports.sh` already allows Accelerate in, so SPS-16 can use it from pure Domain code. Without Accelerate
  (Linux/Windows) it falls back to a plain loop.
- Data: `VisionFeaturePrintExtractor` (`FeaturePrintExtracting`) builds a new request and handler per image inside
  `autoreleasepool`, with `VNImageRequestHandler(cgImage:orientation:options:)`, Revision 2 (Revision 1 only if
  unsupported) and `imageCropAndScaleOption = .scaleFill` fixed as `cropAndScaleOption`. `observation.data` is **copied**
  into `[Float]` (`copyBytes`) rather than `bindMemory`, so misaligned `Data` can't trap; `.double`/unknown element types and
  a size mismatch throw `FeaturePrintExtractionError`.
- `VisionFeaturePrintService` is a stateless `struct`: it loads the image through `ImageLoading.loadImage` (512 px), then
  runs the extractor on a private concurrent `DispatchQueue` (never the main thread, never blocking a Swift-concurrency
  thread) behind `ConcurrencyLimiter`, an internal async semaphore, default width 2 (`defaultMaxConcurrentRequests`).
  The limit is per service instance; image *loads* are not limited by it, so the caller's task-group width bounds them.
  A Vision failure is logged with the asset ID as `.private`.
- `AppContainer` builds a `PhotoKitImageLoader` and passes it in; SPS-17 should share that loader.
- The iOS 18 Swift-native `GenerateImageFeaturePrintRequest` was not added; it can be another `FeaturePrintExtracting`.
- Tests: real-Vision tests on synthetic, code-drawn images (vDSP vs `computeDistance` ≤ 1e-4, same image ≈ 0, orientation
  applied) run **only on a physical device** (`#if os(iOS) && !targetEnvironment(simulator)`), so CI never runs them.
  In the macOS CI virtual machine `swift test` hung for an hour with them (and a `@MainActor` test) in the run. In the
  Simulator the feature-print model is missing (`fopen failed for data file`) and every image gets the same print
  (distance 0): **in the Simulator the app would group unrelated photos**, so never judge clustering there.
  `VisionFeaturePrintDeviceTests` repeats the 1e-4 check on 20 real photos with `RUN_DEVICE_PERFORMANCE_TESTS=1`.
  **Still open on a device:** a test run of `DataTests` on an iPhone (the synthetic-image tests and that device test).
