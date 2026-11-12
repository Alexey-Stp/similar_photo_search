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
- From SPS-16: per session, build `VectorItem(asset:featurePrint:)` for every photo with a vector and call the synchronous `clusters(in:config:)`. `ClusteringConfig.thresholds` has **no default** (calibration spike); a revision without a threshold throws `ClusteringError.missingThreshold`, so surface that as an error, not "no duplicates". `SimilarityCluster.id` is a `String`, so `ClusterUpdate.removed` carries `[String]`, not `[UUID]`. Drop stored clusters when the clustering config changes, as for `sessionConfig`.
- From SPS-17: after clustering a session, reuse `record.quality(scoringVersion: qualityScorer.scoringVersion)` for
  each member and call `qualityScorer.measure(asset)` only for the rest (bounded width; it throws only on
  cancellation). Store hits with `record.withQuality(measurement)` in the same session `upsert` as the prints (don't
  cache skipped or failed measurements), then rank each cluster with
  `QualityRanker().rank(members.mapValues { QualitySignals(measurement:asset:) })`, using the current `PhotoAsset`.

## Implementation notes

- **Where things live.** `AnalysisCoordinator` (Domain `actor`, `ScanCoordinating`) only manages runs; each scan is a
  `ScanRun` actor, so `cancel()` and `excludeDeleted(_:)` never wait behind clustering. Pure Domain, so it is tested on
  Windows/Linux. `ThermalMonitor` (Domain protocol) → `ProcessInfoThermalMonitor` (Data); `ClusterRepository` (Domain,
  the name SPS-20 uses) → `FileClusterRepository` (Data, one JSON file in `Application Support/Results`, excluded from
  backup, `.completeFileProtectionUntilFirstUserAuthentication`, whole file rewritten per `apply`, results batched every
  20 sessions and at the end/cancel). `ScanViewModel` + `ScanStatusSection` (Presentation); `UIKitAppLifecycle` (app
  target) implements the Presentation protocols `IdleTimerControlling` and `BackgroundTaskRunning`.
- **API deviations from the hints.** `start(scope:sessionConfig:)` (the session config comes from `ScopePreferences`,
  not from inside the coordinator) returns `ScanStreams`. `ClusterUpdate.added` carries **`[ClusterSelection]`**, not
  `[SimilarityCluster]`: the coordinator runs `SmartSelectionUseCase` itself (it has the quality signals), so
  `SelectionStore.upsert` takes the payload as is. `.removed` carries `[String]`; `.finished` has no payload (the final
  `ScanProgress.phase` says done / cancelled / failed). `ScanPhase` adds `.failed(ScanFailure)`
  (`missingThreshold(revision:)`, `libraryUnavailable`); `ScanProgress` adds `failed`, `conditions` and `clusterCount`.
- **No delta expansion.** Every scan enumerates the whole scope (metadata only) and segments it; `SessionChangePlanner`
  then marks each multi-photo session unchanged/changed against the stored fingerprints, as the SPS-10 notes suggest.
  That covers "rebuild a session joined or grown by a new photo as a whole" without re-enumerating neighbours, and also
  finds sessions that only lost photos.
- **Stored results.** Only sessions of ≥ 2 photos are stored, also those with no cluster. Clusters are stored without a
  keeper; every scan recomputes the suggestion from cached measurements and the current favorite flags. Results are keyed
  by `ScanResultsKey` (session config + clustering config + feature-print revision): a change of any of them recomputes
  every cluster (prints stay cached) and drops the old results. Every scan re-publishes **all** current groups, reused ones
  too (same IDs, so `SelectionStore` keeps overrides). An ID published in a scan is never also removed in that scan.
- **Throttling.** Width = `ScanConditions.recommendedConcurrency(fullConcurrency: 4)`: nominal/fair 4, Low Power 2,
  serious 1, critical 0 = pause (phase `.throttled`; a cancel still ends it). The width is re-read before each new photo.
  The UI shows "Paused to cool down" and a Low Power notice from `ScanProgress.conditions`.
- **Persistence.** New prints are written every 200 photos of a session (`persistBatchSize`); the last batch goes in one
  `upsert` with the quality measurements. On cancel or failure the work finished so far is upserted first. Cache and
  repository write errors are ignored (they only cost a re-analysis). The change token is committed only after a
  successful scan; an unusable history (preparer error) falls back to fingerprint-only comparison and does not commit.
- **Progress.** `total` is `assetCount(scope:)` (an upper bound for overlapping albums, clamped to `processed`, set to
  `processed` when done). Single-photo sessions, skips and undated photos count as processed. ETA is the average rate
  since analysis began, so cached and single photos make the early estimate optimistic. Throttled by
  `ScanProgressThrottle` (100 ms, phase and condition changes forced); the stream keeps only the newest snapshot.
- **Lifecycle.** The idle timer is off only while `ScanStatusSection` is on screen and a scan runs. Going to the
  background during a scan starts `beginBackgroundTask`; on expiry the scan is cancelled and the task ended inside the
  handler. `BGProcessingTaskRequest` (optional) was **not** added, so Info.plist is unchanged.
- **Thresholds.** `AppContainer.clusteringConfig` has **no threshold** (calibration still open: [SPS-28](SPS-28.md)), so
  on a device every scan currently stops at the first session with two analysed photos and shows "not calibrated".
- **Verified on Windows:** Domain tests (203, incl. `AnalysisCoordinatorTests` (20: publish order, single-photo skip,
  resume from cache, reuse of unchanged sessions, removal of shrunk sessions, config change, cancel < 500 ms with saved
  work, deleted-during-scan, serious/critical/Low Power throttling, batched saves, missing threshold) and
  `ScanProgressTests`), `-warnings-as-errors`; `check-domain-imports.sh`, `check-concrete-construction.sh`,
  `check-privacy-manifest.sh`; `FileClusterRepository` type-checked in a scratch package (Darwin-only calls stubbed).
  **Not run (need macOS CI):** `Packages/Data` tests (`FileClusterRepositoryTests`, `ProcessInfoThermalMonitorTests`),
  Presentation tests (`ScanViewModelTests`), the app build, SwiftLint.
- **Device QA still open:** cancel latency with real Vision (≤ 500 ms), thermal throttling (Xcode ▸ Devices ▸ Condition
  ▸ Thermal State), Low Power notice, background expiry stops cleanly, idle timer, kill mid-scan and relaunch (only the
  rest is analysed), and the zero-network checklist over a full scan, which needs a calibrated threshold first.
