# SPS-17 — Photo quality scoring

**Type:** Technical task · **Epic:** SPS-15 · **Depends on:** SPS-9

## Description

Compute a quality score for each cluster member (lazily, only for assets that end up in clusters) to rank the best shot.

Signals:

- **Sharpness:** variance of the Laplacian on a grayscale 512 px image, normalized within the cluster.
- **Face quality:** `VNDetectFaceCaptureQualityRequest`, mean `faceCaptureQuality` (0…1) over the detected faces (blur, eyes closed, pose).
- **Aesthetics (iOS 18+ only, optional):** `VNCalculateImageAestheticsScoresRequest`, `overallScore`, `isUtility`.
- **Metadata:** resolution (pixelWidth × pixelHeight), `isFavorite`, has edits.

## Acceptance criteria

- Weighted score: `0.4·sharpness + 0.4·faceQuality + 0.1·resolution + 0.1·aesthetics`, in 0…1. Weights are configurable.
- A signal is used for a cluster only if every member has it. If any member lacks it (no faces found, or no aesthetics
  because the device runs iOS 17), its weight is spread over the remaining signals in proportion to their weights, for the
  whole cluster, so the remaining weights again sum to 1 and all members' scores stay comparable (SPS-18's near-tie rule).
- All signals are normalized **within the cluster** (min-max).
- **Given** a favorite asset, **then** it is always protected (never auto-selected for deletion), whatever its score.
- **Given** Vision returns no faces, **then** `faceQuality = nil`, not 0.
- Scores are cached in the analysis cache (SPS-13) together with the scoring version.
- Per-image scoring takes under 60 ms on an iPhone 13 at 512 px.

## Technical notes

Reuse the image loader (SPS-9). Run the face and aesthetics requests in a single `VNImageRequestHandler.perform([...])`.
Laplacian via `vImageConvolve_PlanarF` with kernel `[0,1,0,1,-4,1,0,1,0]`. `VNCalculateImageAestheticsScoresRequest` behind `#available(iOS 18, *)`.

## Risks

Leaked vImage buffers (manual `malloc`) cause memory growth: always `defer { free(buffer.data) }`. A Laplacian on noisy
low-light photos mistakes noise for sharpness; use a light Gaussian pre-blur. Face quality is meaningless for landscapes, so weight redistribution is required.

## Implementation hints

- **Start from** the existing `QualityScorer` protocol and `VisionQualityScorer` placeholder (SPS-2).
- Load images through `ImageLoading` (SPS-9) injected into `VisionQualityScorer`'s initializer; the Domain protocol keeps
  taking asset IDs, and `rawSignals(for: LoadedImage, …)` stays inside Data.
- Data: `func rawSignals(for image: LoadedImage, asset: PhotoAsset) async throws -> QualitySignals` with
  `struct QualitySignals: Sendable { sharpness: Float; faceQuality: Float?; aesthetics: Float?; isUtility: Bool?; pixelCount: Int; isFavorite: Bool; isEdited: Bool }`.
- Domain (pure): `func rank(_ signals: [String: QualitySignals], weights: QualityWeights) -> [RankedMember]`, min-max per
  cluster, best first, with `reasons` ("Sharpest", "Best faces"). Reasons shown in the UI must be localizable keys, not English strings.
- Sharpness: Planar8 grayscale via `vImageConvert`, then PlanarF, convolve, variance via `vDSP.meanSquare`/`mean`.
- Tests: blurred vs sharp fixture → sharper wins; nil-face weight redistribution; favorites passthrough.
- From SPS-13: `CachedAnalysis` v1 has only `qualityScore: Double?` and no scoring version. Scores are min-max normalized per cluster, so cache the raw per-photo signals (or a raw score) with a scoring version, not the normalized score: add them in `AnalysisSchemaV2` with a stage in `AnalysisMigrationPlan`.

## Implementation notes

- **Protocol reworked, as SPS-12 did:** `QualityScorer.measure(_: PhotoAsset) async throws -> QualityOutcome`
  (`.measured(QualityMeasurement)`, `.skipped(SkipReason)`, `.failed(.vision)`) plus `scoringVersion`. It takes the
  `PhotoAsset`, not an ID, and throws only `CancellationError`. The SPS-2 `score(assetID:) -> Double` had no callers.
- **Raw, cached vs. ranked:** `QualityMeasurement` (Domain) holds only the expensive raw values (Laplacian variance,
  face quality, aesthetics, `isUtility`, `isEdited`) and its `version`. `QualitySignals(measurement:asset:)` adds
  `pixelCount` and `isFavorite` from the **current** `PhotoAsset`, so a favorite set later is never missed.
  `QualityRanker` (Domain/Quality, pure struct) turns `[assetID: QualitySignals]` into `[RankedMember]`
  (`score` 0…1, `isProtected`, `reasons`), best first, ties by asset ID.
- Ranking rules beyond the criteria: a signal counts only if every member has a **finite** value and its weight is
  above 0 (negative weights count as 0); a signal equal for all members normalizes to 1 and gives no reason; with no
  usable signal every score is 0. Favorites are marked `isProtected` with a `.favorite` reason but keep their place in
  the score order. Members without a measurement (skipped/failed) are simply not in the input: the ranker never
  invents a score for them.
- `isUtility` is measured and cached but not weighted. `QualityWeights.standard` is 0.4 / 0.4 / 0.1 / 0.1; weights
  need not sum to 1 (the score divides by the sum of the used ones).
- `QualityReason` raw values are the string-catalog keys `quality.reason.*` (added to Presentation's
  `Localizable.xcstrings`); nothing shows them yet.
- `scoringVersion = 1000 · VisionQualityScorer.algorithmVersion + 10 · face-request revision + (aesthetics ? 1 : 0)`,
  so an iOS update that adds aesthetics or a new face revision re-measures photos. Bump `algorithmVersion` when the
  sharpness kernels or the image size change.
- **Cache:** `AnalysisSchemaV2` replaces V1's never-written `qualityScore` with `qualityVersion`, `qualitySharpness`,
  `qualityFaceScore`, `qualityAesthetics`, `qualityIsUtility`, `qualityIsEdited` (all optional), with a lightweight
  V1 → V2 stage, so cached feature prints survive. `AnalysisRecord.qualityScore` became `quality: QualityMeasurement?`,
  with `quality(scoringVersion:)` and `withQuality(_:)`. A measurement lives inside its record, so a new feature-print
  revision or an edit to the photo drops it too.
- Data: `SharpnessMeter` (vImage: Planar8 gray → PlanarF, 3×3 binomial pre-blur, Laplacian, edge extend, variance in
  `Double`, every buffer freed in `defer`); `VisionQualityExtractor` (`VNDetectFaceCaptureQualityRequest` at the newest
  supported revision, plus `VNCalculateImageAestheticsScoresRequest` on iOS 18 / macOS 15, in one `perform`);
  `PhotoKitAssetEditInspector` (`AssetEditInspecting`: edited = an `.adjustmentData` or `.fullSizePhoto` resource;
  lists resources only, no data and no network). `VisionQualityScorer` is now a stateless `struct` (was an `actor`)
  shaped like `VisionFeaturePrintService`: loads 512 px through the shared `PhotoKitImageLoader`, works on its own
  concurrent queue in one `autoreleasepool`, and has its **own** `ConcurrencyLimiter` (2), separate from the
  feature-print one.
- Failures: any Vision error (also from the aesthetics request) or a vImage error gives `.failed(.vision)`; a photo
  gone before the edit check gives `.skipped(.notFound)`. Neither is cached by the scorer.
- Not wired into a scan yet: SPS-14 calls the scorer and the ranker. `AppContainer` builds the scorer with the
  shared image loader and a `PhotoKitAssetEditInspector`.
- Tests: `QualityRankerTests` and `AnalysisRecordTests` (Domain); `SharpnessMeterTests` (sharp vs blurred, flat,
  rotation, noise), `VisionQualityScorerTests` (mocks: outcomes, skips, failures, concurrency, cancellation),
  cache round trip and V1 → V2 migration in `SwiftDataFeaturePrintCacheTests` (Data, macOS CI).
- **Device-only, still open:** `QualityScoringDeviceTests` on an iPhone: real Vision gives `faceQuality == nil` for
  a picture without faces (and aesthetics on iOS 18), and the mean per-image time is under 60 ms on an iPhone 13
  (`RUN_DEVICE_PERFORMANCE_TESTS=1`). Also open: tuning the weights on the labelled fixture set, like the threshold.
