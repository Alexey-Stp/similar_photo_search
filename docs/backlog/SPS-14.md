# SPS-14 — Analysis orchestrator: progress, cancellation, resume, thermal awareness

**Type:** User story · **Epic:** SPS-11 · **Depends on:** SPS-9, SPS-12, SPS-13, SPS-16, SPS-26 (SPS-10 and SPS-17 when available)

## User story

As a user with a large library, I want to see scan progress, pause or cancel it, and have it continue where it stopped, so
that I don't lose time or battery.

## Acceptance criteria

- `AnalysisCoordinator` works **session by session, newest first**: enumerate assets by date (SPS-7, or the delta from
  SPS-10) → split into sessions (SPS-26) → skip single-photo sessions → for each session:
  (with a delta, first expand the changed IDs to the **whole** sessions they touch: re-enumerate the unchanged neighbours
  within `sessionGap` of each changed photo, repeating until the session edges are found, and only then segment and drop
  single-photo sessions, so a session joined or grown by a new photo is rebuilt as a whole; newest-first order is kept) take cached vectors (SPS-13), load
  images and extract feature prints only for the missing ones (SPS-9, SPS-12), cluster the session (SPS-16), score the
  members (SPS-17), save, and **publish that session's groups immediately**.
- Groups are published through a separate `AsyncStream<ClusterUpdate>` (`.added([SimilarityCluster])`, `.removed([ClusterID])`, `.finished`), independent of progress.
- Sessions are published in date order (newest first), so the UI only appends. Image work inside a session runs in parallel with a bounded width.
- **Given** the scan is running, **when** the user deletes photos from groups already shown, **then** the scan continues and the deleted IDs are never loaded or analysed.
- Progress is published as `AsyncStream<ScanProgress>` (processed, total, skipped, ETA), throttled to at most 10 updates/s.
- **Given** the user taps Cancel, **then** work stops within 500 ms and finished results stay saved.
- **Given** the app is killed mid-scan, **when** relaunched, **then** only unprocessed assets are analysed (falls out of the cache-validity check).
- **Given** `ProcessInfo.thermalState` is `.serious` or `.critical`, **then** concurrency drops to 1, and the UI shows "Paused to cool down" at `.critical`.
- **Given** Low Power Mode is on, **then** concurrency drops and the user sees a notice.
- **Given** the app goes to the background, **then** the scan continues for its granted time (`beginBackgroundTask`), then
  stops cleanly. Optional: a `BGProcessingTaskRequest` (`requiresExternalPower = true`) finishes overnight.
- `UIApplication.shared.isIdleTimerDisabled = true` only while the scan screen is visible.
- The zero-network manual QA ([docs/qa/zero-network.md](../qa/zero-network.md)) passes over a full scan.

## Technical notes

The coordinator is an `actor`. Observe `ProcessInfo.thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange`.
`BGTaskScheduler` needs `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes = processing` in Info.plist
(`processing` is allowed; `fetch` and `remote-notification` are forbidden by `scripts/forbidden-plist-keys.txt`).
The scan scope comes from `ScopePreferences.scanScope(now:calendar:)` (SPS-8).

## Risks

Heat and battery drain lead to bad reviews, so throttling is a must. Background-task expiry handlers must finish quickly or
iOS kills the app. `cancel()` during a half-done SwiftData save needs transactional batching.

## Implementation hints

- Dependencies (protocols): `PhotoLibraryRepository`, `LibraryChangeTracker`, `FeaturePrintCache`,
  `FeaturePrintService` (it loads images itself; `ImageLoading` is Data-only, see SPS-9), `ThermalMonitor`, `SessionSegmenter`, `ClusteringEngine`, `QualityScorer`.
- API: `func start(scope: ScanScope) -> (progress: AsyncStream<ScanProgress>, clusters: AsyncStream<ClusterUpdate>)`;
  `func cancel()`; `func excludeDeleted(_ ids: Set<String>)`.
- `enum ClusterUpdate: Sendable { case added([SimilarityCluster]), removed([UUID]), finished }`.
- `struct ScanProgress: Sendable { processed: Int; total: Int; skipped: [SkipReason: Int]; phase: Phase; eta: TimeInterval? }`,
  phases: enumerating, analyzing, clustering, done, cancelled, throttled.
- Bounded `TaskGroup` width from `ThermalMonitor.recommendedConcurrency` (nominal/fair 4, serious 1, critical 0 = pause).
  Throttle progress to 100 ms; persist in batches of 200; `autoreleasepool` per image.
- Skip counts use Domain `SkipReason` (SPS-9 added `iCloudOnly`, `decodeFailed`, `notFound`; SPS-26 adds "no date").
  `ImageLoading.loadBatch` delivers in completion order and only loads `maxConcurrent` ahead of its consumer.
- `ScanViewModel` (`@Observable @MainActor`) consumes the streams, exposes percentage and ETA text, handles `scenePhase`.
- Tests with mocks: cancellation latency, resume (cached IDs skipped), thermal throttling, publish order = session order.
- From SPS-26: `SessionSegmenter` is a concrete struct (inject it as is, no protocol) that yields `.session` events and a final `.finished(summary)`; map `summary.skippedNoDateCount` to `SkipReason.noDate`, take the config from `ScopePreferences.sessionConfig`, and drop stored clusters when it changes (feature prints stay valid).
- From SPS-12: call `featurePrint(for: PhotoAsset)`; it returns `.computed`/`.skipped(SkipReason)`/`.failed(.vision)` and throws only on cancellation. Use `featurePrintService.revision` for cache lookups. It caps Vision at 2 requests itself, but not image loads: keep the task-group width bounded.
- From SPS-13: per session, `validEntries(for: session.assets, revision: featurePrintService.revision)` gives the hits; a `.failed` hit has no vector and must not be re-run. Turn outcomes into records with `AnalysisRecord(outcome:asset:revision:analyzedAt:)` (skips return `nil` and are not cached) and pass the whole session to one `upsert` (it saves every 200 itself). `upsert` replaces the whole record, score included, so write the print and the score together or carry the old score over.
- From SPS-10: start with `IncrementalScanPreparer.prepare()` (before enumerating; it purges deleted IDs) and call `LibraryChangeTracker.commitScanCompleted()` only after a successful scan. Store each session's `SessionFingerprint` with its clusters and classify every new session with `SessionChangePlanner` (`.unchanged` → reuse stored clusters, `.changed` → cache lookup, Vision for misses, re-cluster); drop the results of `staleSessionIDs` (deleted IDs have no dates, so full metadata enumeration plus fingerprints is what finds sessions that only lost photos). Subscribe to `LibraryChangeObserving.changes()` while in the foreground to trigger an incremental scan.
