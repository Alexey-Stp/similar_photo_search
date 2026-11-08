# SPS-26 — Split the library into shooting sessions by time

**Type:** Technical task · **Epic:** SPS-6 · **Depends on:** SPS-7

## Description

Core product rule: similar photos are taken close together in time. `SessionSegmenter` (pure Domain logic) takes the
date-sorted asset stream from SPS-7 and cuts it into shooting sessions. A session is a run of photos where every gap between
neighbouring shots is at most `sessionGap` (default 15 min). Sessions are the only unit that is ever compared (SPS-16) and
the unit of live results (SPS-14). Sessions with a single photo are marked `needsAnalysis = false` and never reach Vision.

## Acceptance criteria

- **Given** photos at 10:00, 10:05 and 10:40 with `sessionGap` 15 min, **then** the output is two sessions: [10:00, 10:05]
  (needs analysis) and [10:40] (single photo, skipped).
- **Given** photos at 23:55 and 00:05 the next day, **then** they are in one session: the rule is the gap between shots, not the calendar day.
- **Given** two photos more than `sessionGap` apart with no photos between them, **then** they are never in the same session.
- **Given** a burst (same `burstIdentifier`) or equal timestamps, **then** all of them are in the same session.
- **Given** a session grows past `maxSessionSize` (default 500, for example an import where all items have nearly the same
  date), **then** it is split at its largest internal time gap, and the split is logged.
- **Given** an asset without `creationDate`, **then** it is not put into any session and is counted in the scan summary as "skipped (no date)".
- Streaming: a session is emitted as soon as the next asset shows a gap larger than `sessionGap`; the segmenter does not wait
  for the whole library. The last session is emitted when the input ends.
- Cancellation of the consuming task stops the segmenter at once.
- `sessionGap` is configurable in Settings (Strict 5 min / Balanced 15 min / Relaxed 60 min); changing it invalidates
  clusters but **not** the feature-print cache.
- Debug builds log how many photos were skipped as single-photo sessions, so the saving can be measured on real libraries.

## Technical notes

Pure Swift in `Domain`, no PhotoKit. `AsyncThrowingStream<[PhotoAsset], Error>` (pages from SPS-7) →
`AsyncThrowingStream<PhotoSession, Error>`. Input is newest first, so the gap is `previous.creationDate - current.creationDate`.
The session ID must be stable between runs for the same set of photos, so cached results can be matched.
Storing `sessionGap` uses UserDefaults: already declared in the privacy manifest.

## Risks

A gap that is too small splits a real series (a sunset shot over 30 minutes), and those photos are never compared; calibrate
`sessionGap` on the labelled fixture set together with the similarity threshold. Wrong dates (scans, imports, messenger
saves) put unrelated photos into one huge session; Vision distance still stops false groups, and `maxSessionSize` bounds the
cost. Unstable session IDs make cached results unusable.

## Implementation hints

- `struct SessionConfig: Sendable { sessionGap: TimeInterval = 900; maxSessionSize: Int = 500 }`.
- `func sessions(from pages: AsyncThrowingStream<[PhotoAsset], Error>, config: SessionConfig) -> AsyncThrowingStream<PhotoSession, Error>`
  plus a counter of assets skipped for missing dates.
- `struct PhotoSession: Sendable, Identifiable { id: String; assets: [PhotoAsset]; dateRange: ClosedRange<Date>; needsAnalysis: Bool }`,
  `needsAnalysis == assets.count >= 2`, id e.g. the newest asset's `localIdentifier` + its `creationDate` timestamp.
- SPS-7 already delivers undated photos last and keeps equal timestamps on one page, so the segmenter can stop dated
  sessions at the first undated asset.
- Split oversized sessions recursively at the largest internal gap. `onTermination` cancels the reading task.
- Tests (Swift Testing): the 10:00/10:05/10:40 example, 23:55 → 00:05, two photos on different days, bursts with equal
  timestamps, nil dates, `maxSessionSize` split, streaming (first session before the input finishes), stable IDs across two runs.
