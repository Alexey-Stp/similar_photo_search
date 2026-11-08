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
- Set `revision = VNGenerateImageFeaturePrintRequestRevision2`; fall back to Revision1 and record it if unavailable.
- Copy `observation.data` into `[Float]` with `withUnsafeBytes` + `bindMemory` and `elementCount`.
- `enum VectorMath { static func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float }` with vDSP and a precondition on
  equal counts. Accelerate is allowed in Domain only for the clustering engine, so put `VectorMath` where SPS-16 can use it.
- Tests: on-device comparison with `computeDistance` for two bundled images (tolerance 1e-4); identical images ≈ 0. Mark
  Neural-Engine tests device-only (same `RUN_DEVICE_PERFORMANCE_TESTS` pattern as SPS-7).
