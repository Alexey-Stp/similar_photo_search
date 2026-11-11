# SPS-28 — Calibrate the similarity threshold and session gap on a labelled set

**Type:** Spike + technical task · **Epic:** SPS-27 · **Depends on:** SPS-12, SPS-16, SPS-17, SPS-26

## Description

The app cannot find duplicates on a device yet. `AppContainer.clusteringConfig` is `ClusteringConfig(thresholds: [:])`, so
every scan stops at the first session with two analysed photos and throws `ClusteringError.missingThreshold`
("not calibrated"). This was the sprint-2 spike from the backlog index, and it never got a ticket.

Build a labelled set of at least 500 photos with "same / not same" pairs. Use it to pick the Euclidean distance threshold
for Vision feature-print revision 2 and to confirm the default `sessionGap` (15 min). Commit the set as a regression
fixture, so every later change to clustering or to the feature-print revision is measured against it.

## Acceptance criteria

- **Given** the labelled set, **then** a fixture in the repo holds, for each photo, its revision-2 feature print (raw
  `[Float]` + revision, as in the cache), `creationDate`, `burstIdentifier`, and a group label. It holds **no image
  pixels**, so no personal photo is committed.
- The set has at least 500 photos and covers bursts, the same scene re-framed, the same scene with a different subject,
  screenshots, documents and receipts, night and low-light shots, and unrelated photos taken within a few minutes of
  each other.
- A calibration test in `DomainTests` runs `UnionFindClusteringEngine` per session on the fixture and reports pairwise
  precision and recall. It fails if precision drops below **95 %** or recall below **80 %** (the SPS-15 epic target).
- `AppContainer.clusteringConfig` gets a threshold for revision 2, chosen from the precision/recall curve. Its doc
  comment states the dataset size, the measured precision and recall, and the date.
- **Given** the same fixture, **then** the session-gap choice (5 / 15 / 60 min) is measured for recall: how many labelled
  pairs land in different sessions. Keep or change the 15 min default from that number, and record the result.
- **Given** a device scan of a real library, **then** groups appear and no scan ends in "not calibrated" for revision-2
  prints.
- Implementation notes record the method, the curve (or a table of threshold → precision / recall), and the chosen values.

## Technical notes

- Feature prints must come from a **physical device**: the Simulator gives different vectors (CLAUDE.md).
- Extract the vectors with a debug-only path, for example a test on a device that reads a labelled album and writes a JSON
  file. Nothing may use the network, and the path must not ship in Release.
- Use photos the team owns and agrees to have in the repo as vectors.
- Possible follow-ups, out of scope here: the Strict / Balanced / Relaxed threshold setting (SPS-16 risks), and tuning the
  quality-score weights on the same set (SPS-17 notes). Each needs this calibration first.

## Risks

Too small or too uniform a set gives a threshold that fails on real libraries. One person's camera habits can bias it. An
iOS update can ship a new feature-print revision, which then needs its own threshold (the engine throws for a revision
without one, which is the intended behaviour).

## Implementation notes

**Status: tooling done, device part open.** Built and tested on Windows without a device; the fixture, the threshold and
the device scan still need a physical iPhone. Until the fixture is committed, `CalibrationTests` **fails on purpose**
(three tests: "fixture missing"), so `swift test` for Domain and the app's test scheme are red.

- **Method.** The labelled set is one album per group inside a top-level Photos folder `SPS-Calibration`, named
  `<category>--<label>` (`burst`, `reframed`, `different-subject`, `screenshot`, `document`, `low-light`, `unrelated`;
  in an `unrelated--…` album every photo is its own group). Step-by-step procedure:
  `Packages/Domain/Tests/DomainTests/Fixtures/README.md`. Scoring is **pairwise** over all labelled pairs of the
  fixture: photos are cut into sessions with the real `SessionSegmenter` (default `maxSessionSize`), each session is
  clustered with the real `UnionFindClusteringEngine`, and a labelled pair in different sessions counts as a false
  negative. So the session gap shows up in recall, and the score matches what a scan would show.
- **Fixture** `Packages/Domain/Tests/DomainTests/Fixtures/calibration-rev2.json` (a `DomainTests` resource):
  `CalibrationFixture` format 1, per photo `id`, `group`, `category`, `creationDate` (seconds since 1970), optional
  `burstIdentifier`, `revision`, `vector` (base64 of little-endian `Float`s, the cache's packed bytes). It is anonymous:
  photos `p0001…` in date order, bursts `b1…`, groups `<category>-g1…`. No PhotoKit IDs, album titles or pixels.
- **Where the code lives.** `CalibrationFixture`, `CalibrationFixtureBuilder` (album-name parsing, anonymization,
  rejects a photo in two albums, a missing date or a foreign print), `CalibrationEvaluator` (score, curve,
  `bestPoint` = best recall at precision ≥ the minimum, smallest threshold on ties, `sessionGapSplits`) and
  `CalibrationReport` (Markdown tables) are in **`DomainTestSupport`**, so they never ship in the app. `DataTests` now
  depend on `DomainTestSupport`.
- **Extraction** is `CalibrationFixtureExtractionTests` (DataTests). It is compiled only for an iOS device and
  enabled only with `RUN_CALIBRATION_EXTRACTION=1`. It uses the app's own `VisionFeaturePrintService` (512 px,
  `isNetworkAccessAllowed = false`) and fetches with `includeAllBurstAssets = true`. It writes the JSON as a Swift
  Testing attachment (`#if compiler(>=6.2)`) and to the temporary directory, and fails if any photo got no print
  (iCloud-only) or there are fewer than 500 photos.
- **Deviation: the threshold lives in Domain.** It is `ClusteringConfig.calibrated`, and
  `AppContainer.clusteringConfig` is now just `ClusteringConfig.calibrated`. The calibration test checks that exact
  config, so the app and the regression gate can't drift apart. The doc comment with dataset size, precision, recall
  and date goes on `ClusteringConfig.calibrated`. It is still `thresholds: [:]`.
- `CalibrationTests` prints the coverage table, the curve (thresholds 0.00–1.50 in 0.01 steps; rows with no true
  positive are left out) and the session-gap table for 5 / 15 / 60 min. It fails if the set has fewer than 500 photos,
  a category with no group (`unrelated` needs at least 2), a non-revision-2 print, or no burst; if precision < 95 % or
  recall < 80 % at the calibrated config; or if the default 15 min gap alone caps recall below 80 %.
- Checked with a throwaway synthetic 504-photo fixture (not committed): the resource loads, the tables print, and the
  test stops at "no threshold for revision 2". Synthetic numbers say nothing about real prints.
- Windows: SwiftPM writes the test resource bundle's `Info.plist` into `Packages/Domain/`; it is now in `.gitignore`.

### Still open (device)

1. Build the albums (≥ 500 photos, all categories, more than one photographer), run the extraction on an iPhone, and
   commit `calibration-rev2.json`.
2. Run `CalibrationTests`, put the chosen threshold in `ClusteringConfig.calibrated` with its doc comment, and record
   here: the curve table, the chosen threshold with precision and recall, and the session-gap table with the decision
   to keep or change 15 min.
3. Device scan of a real library: groups appear and no scan ends in "not calibrated".
4. Not run here: `swift test` for `Packages/Data` (the extraction test, the new `DomainTestSupport` dependency), the app
   build and SwiftLint (macOS only).
