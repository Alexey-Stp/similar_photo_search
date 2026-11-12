# SPS-34 — Tune the quality-score weights on the labelled set

**Type:** Spike + technical task · **Epic:** SPS-15 · **Depends on:** SPS-17, SPS-18, SPS-28

## Description

Smart Selection keeps the photo with the best weighted quality score. The weights, `QualityWeights.standard`
(0.4 sharpness, 0.4 face quality, 0.1 resolution, 0.1 aesthetics), were set by hand in SPS-17, whose notes leave
"tuning the weights on the labelled fixture set" open, and picking the wrong "best" photo erodes trust (SPS-15 risks).
Measure how often the ranker agrees with a person's choice, and tune the weights on that number. Optional: the first
release doesn't need it.

The SPS-28 fixture can't do this yet: it holds feature prints and group labels, but no quality values and no "best
photo" label.

## Acceptance criteria

- The fixture gains, per photo, the raw `QualityMeasurement` values (sharpness, face quality, aesthetics, `isUtility`,
  `isEdited`) with their `scoringVersion` and the pixel count, and per group the photo a person picked as the best.
  Still no pixels and no PhotoKit IDs. The format version goes up; an old fixture is re-extracted, never mixed in.
- `CalibrationFixtureExtractionTests` records these values on a device with the app's own `VisionQualityScorer`, which
  loads 512 px images with `isNetworkAccessAllowed = false` as before.
- A test in `DomainTests` runs `SmartSelectionUseCase` on every labelled group and reports, for the standard weights
  and for each candidate: how often the picked photo is the suggested keeper (top-1), and how often it is pre-selected
  for deletion.
- `QualityWeights.standard` changes only if the new weights raise top-1 agreement and pre-select the picked photo no
  more often. Its doc comment states the dataset size, both numbers and the date, and the test gates them, as
  `CalibrationTests` does for the threshold.
- The implementation notes record the method, the candidates tried and their numbers.

## Technical notes

- How a person marks "best" is open. Options: a Favorite in the calibration library (the builder then records it as
  the label, not as a real favorite, which `QualitySignals` would protect), or one extra album per group for the
  keeper (`CalibrationFixtureBuilder` rejects a photo in two albums today, so that rule needs an exception). Pick one
  and document it in `Packages/Domain/Tests/DomainTests/Fixtures/README.md`.
- Aesthetics exist only on iOS 18 or later (SPS-17). Extract on such a device, or the aesthetics weight can't be tuned.
- A grid search over a few weight sets is enough. Keep the near-tie tolerance (0.02, SPS-18) fixed, or tune it in the
  same run and say so.

## Implementation notes
