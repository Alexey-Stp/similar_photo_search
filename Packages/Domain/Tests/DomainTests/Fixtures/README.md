# Calibration fixture (SPS-28)

`calibration-rev2.json` is the labelled set that `CalibrationTests` measures clustering against. It holds, per photo,
the Vision revision-2 feature print (base64 of little-endian `Float`s, the cache's packed bytes), the creation date, an
anonymous burst ID and an anonymous group label. **No image pixels, PhotoKit IDs or album titles.** Photos with the same
group are "the same picture"; every other pair is "not the same".

Until the file exists, `CalibrationTests` is skipped (the test log says so); once it is committed, the suite runs and
fails if the set is incomplete or the calibrated threshold misses the target.

## Extracting it

Vectors must come from a **physical iPhone**: the Simulator has no feature-print model and gives every photo the same print.
Use only photos the team owns and agrees to have in the repo as vectors.

1. On the iPhone, make a top-level folder named **`SPS-Calibration`** in the Photos app. Inside it, make one album per group,
   named `<category>--<label>`. Labels can be anything; they never reach the fixture.

   | Category | One album holds |
   |---|---|
   | `burst` | the frames of one burst (keep it as a burst, so the burst identifier is used) |
   | `reframed` | one scene shot several times: zoomed, stepped aside, portrait and landscape |
   | `different-subject` | one subject in one scene; the same scene with another subject goes in another album |
   | `screenshot` | screenshots of the same screen |
   | `document` | shots of the same document or receipt |
   | `low-light` | night or low-light shots of the same scene |
   | `unrelated` | photos that are **not** the same, taken within a few minutes of each other; each is its own group |

   A photo must be in exactly one album. Keep the originals on the device (iCloud-only originals are skipped, never
   downloaded). Aim for at least 500 photos in total, with several albums per category, from more than one person's camera
   habits. The set is rejected (`CalibrationCoverage`) unless every category except `unrelated` has an album with at
   least two photos, `different-subject` has at least two albums, `unrelated` has at least two photos, and at least one
   burst contributes two or more frames. `unrelated` and `different-subject` photos must also be **taken close to photos
   of another album** (same 15 min session, at most 60 min apart): only then does the app compare them, and only then
   does the set test precision at all.
2. Build with **Xcode 26 or later** (Swift 6.2). The fixture leaves the device only as a Swift Testing attachment, which
   older toolchains don't have; with them the test fails and says so. Allow the test runner full photo-library access,
   set the scheme's test environment variable `RUN_CALIBRATION_EXTRACTION=1`, and run
   `CalibrationFixtureExtractionTests` (DataTests) on the iPhone.
3. The test prints the coverage table. If every photo got a feature print and the coverage rules above hold, it records
   `calibration-rev2.json` as a test attachment; otherwise it fails and records nothing. In the Xcode test report, select
   the test, export the attachment and put it in this folder.
4. Run `swift test --package-path Packages/Domain --filter CalibrationTests`. It prints the threshold → precision / recall
   curve and the session-gap table. Pick the threshold with the best recall at precision ≥ 95 % and put it in
   `ClusteringConfig.calibrated`, with the dataset size, precision, recall and date in its doc comment. Record the tables in
   `docs/backlog/SPS-28.md`.
