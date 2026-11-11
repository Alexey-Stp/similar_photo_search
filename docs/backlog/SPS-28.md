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
