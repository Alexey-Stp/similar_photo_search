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

- Weighted score: `0.4·sharpness + 0.4·faceQuality + 0.1·resolution + 0.1·aesthetics`. Weights are configurable; when no
  faces are found, the face weight is spread over the other signals.
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
- Data: `func rawSignals(for image: LoadedImage, asset: PhotoAsset) async throws -> QualitySignals` with
  `struct QualitySignals: Sendable { sharpness: Float; faceQuality: Float?; aesthetics: Float?; isUtility: Bool?; pixelCount: Int; isFavorite: Bool; isEdited: Bool }`.
- Domain (pure): `func rank(_ signals: [String: QualitySignals], weights: QualityWeights) -> [RankedMember]`, min-max per
  cluster, best first, with `reasons` ("Sharpest", "Best faces"). Reasons shown in the UI must be localizable keys, not English strings.
- Sharpness: Planar8 grayscale via `vImageConvert`, then PlanarF, convolve, variance via `vDSP.meanSquare`/`mean`.
- Tests: blurred vs sharp fixture → sharper wins; nil-face weight redistribution; favorites passthrough.
