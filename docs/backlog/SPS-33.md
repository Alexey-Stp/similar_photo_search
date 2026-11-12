# SPS-33 — Similarity sensitivity setting: Strict, Balanced, Relaxed

**Type:** Story · **Epic:** SPS-15 · **Depends on:** SPS-28

## Description

SPS-28 calibrates one revision-2 threshold: the best recall at precision ≥ 95 %. Some users want only near-identical
shots; others want every variation of a scene and accept more review. Offer three sensitivities, each with its own
calibrated threshold, and let the user pick one. The SPS-16 risks and the SPS-28 notes name this as a follow-up of the
calibration. Optional: the first release doesn't need it.

## Acceptance criteria

- A Domain preset with three cases (working name `SimilarityPreset`: `strict`, `balanced`, `relaxed`) maps to a
  `ClusteringConfig`. Balanced is today's `ClusteringConfig.calibrated`.
- The Strict and Relaxed thresholds come from the SPS-28 curve: Strict takes the best recall at precision ≥ 99 %,
  Relaxed the best recall at precision ≥ 90 %. If the curve can't reach a target, the notes say why and which point was
  taken, and that point's measured precision becomes the preset's floor. Each threshold's doc comment states dataset
  size, precision, recall and date, like `ClusteringConfig.calibrated`.
- `CalibrationTests` checks all three configs on the fixture. Each meets its precision floor: 99 % for Strict, 95 % for
  Balanced (with recall ≥ 80 %, the SPS-15 target) and 90 % for Relaxed, or the recorded precision of a fallback point,
  which passes when it meets that value. Strict has the highest precision of the three and Relaxed the highest recall.
- The choice is saved in `ScopePreferences`; values saved before this ticket decode as Balanced, as for `sessionGap`.
- **Given** the user changes the sensitivity, **then** the next scan recomputes the clusters from cached feature
  prints: no photo is analysed again.
- The picker sits in `ScopeSelectionView` next to the session gap, with a one-line explanation per choice, VoiceOver
  labels, Dynamic Type, Dark Mode, and its strings in `Localizable.xcstrings`.

## Technical notes

- `AppContainer.clusteringConfig` is a fixed `static let` handed to `AnalysisCoordinator` once. Pass the config per
  scan instead, the way `start(scope:sessionConfig:)` takes the session config (SPS-14).
- `StoredSessionResult` already keys stored results by the thresholds and the other clustering parameters, so old
  clusters aren't reused after a change. Check that the change rescans existing sessions too, not only new ones.
- `CalibrationEvaluator.bestPoint` already finds the best recall at a minimum precision; reuse it with 0.99 and 0.90.
- The session gap presets use the same three names (`SessionGapPreset`). Decide whether to show two pickers or one
  combined choice; two pickers that both read "Balanced" can confuse.
- Relaxed groups hold less similar photos, so Smart Selection may pre-select photos the user wants to keep. Decide
  whether Relaxed groups are always marked `needsReview`.

## Implementation notes
