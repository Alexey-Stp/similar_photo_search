# SPS-13 — SwiftData feature print cache

**Type:** Technical task · **Epic:** SPS-11 · **Depends on:** SPS-12

## Description

Save vectors and analysis metadata so later launches skip Vision for unchanged assets.

## Acceptance criteria

- `@Model final class CachedAnalysis` with `@Attribute(.unique) assetID: String`, `vectorData: Data` (packed `[Float]`;
  `.externalStorage` is not needed below ~3 KB), `revision: Int`, `modificationDate: Date?` (from `PHAsset.modificationDate`),
  `qualityScore: Double?`, `status: String` (analyzed/skipped/failed), `analyzedAt: Date`.
- The cache is valid only if `assetID` matches, `revision` equals the current revision, and `modificationDate` is unchanged. Otherwise the asset is re-queued.
- Writes are batched: insert and `save()` every 200 records through a `@ModelActor`, never from the main context.
- Deleted assets (SPS-10 or the deletion flow) are purged from the cache.
- A `VersionedSchema` plus `SchemaMigrationPlan` is in place from v1.
- **Given** the store is corrupt or fails to open, **then** the app deletes the store file, logs locally (`os.Logger`,
  privacy `.private`) and rebuilds; it does not crash.
- Bulk read of 50k vectors takes under 1.5 s (`propertiesToFetch`, no relationships).
- The store lives in Application Support, is excluded from backup (`isExcludedFromBackup = true`), and has file protection
  `.completeUntilFirstUserAuthentication`, so background processing can still read it.

## Technical notes

`ModelContainer`, `ModelConfiguration(url:)`, `@ModelActor actor AnalysisStore`, `FetchDescriptor` with `#Predicate`.
Revision2 is about 768 floats ≈ 3 KB per vector, so 50k vectors ≈ 150 MB: load vectors **one session at a time**, never the whole table (SPS-16, SPS-26).

## Risks

`ModelContext` and model objects are not `Sendable`: return value types from the actor, never `@Model` instances. Saving
one record at a time is very slow. Concurrent upserts on a unique key must go through the actor's serial execution.

## Implementation hints

- **Start from** the existing `FeaturePrintCache` protocol and the `SwiftDataFeaturePrintCache` placeholder (SPS-2); extend
  the protocol with batch and session-range methods rather than adding a parallel one.
- `enum AnalysisSchemaV1: VersionedSchema` with `CachedAnalysis`; `AnalysisMigrationPlan` with `stages: []`.
- Store API: `validEntries(for:currentRevision:modDates:)`, `upsert(_:)` (save every 200), `purge(ids:)`,
  `vectors(createdBetween:revision:)`.
- Convert `[Float]` ↔ `Data` with `withUnsafeBufferPointer` / `withUnsafeBytes` (no per-element loops).
- `ModelContainerFactory.make()` storing at Application Support/Analysis.store; on load failure delete the store files
  (including `-wal`/`-shm`) and retry once.
- Tests: in-memory `ModelConfiguration(isStoredInMemoryOnly: true)`; invalidation on revision and modification-date change; float round trip.
- From SPS-12: a print can end as `FeaturePrintOutcome.failed(.vision)`; store it with status `failed` under the same revision/modification-date rule so the photo is not re-run through Vision on every scan.

## Implementation notes

- **Protocol reworked, not extended:** `FeaturePrintCache` is now `validEntries(for: [PhotoAsset], revision:) async ->
  [String: AnalysisRecord]` (never throws; an unreadable store is all misses), `upsert(_: [AnalysisRecord]) async throws`
  and `purge(assetIDs:) async throws`. The SPS-2 single-item `cachedFeaturePrint(for:revision:modificationDate:)` and
  `store(_:)` had no callers and were removed. `validEntries` takes `PhotoAsset`s because they carry the modification date
  of the cache key, so the hinted `modDates:` dictionary is not needed.
- **No `vectors(createdBetween:revision:)`:** the model has no photo creation date (not in the criteria), and a session is
  a list of photos anyway. "One session at a time" is `validEntries(for: session.assets, revision:)`.
- Domain value type `AnalysisRecord` (+ `AnalysisStatus`: `analyzed`/`skipped`/`failed`) owns the validity rule
  `isValid(for:revision:)`; `MockFeaturePrintCache` and the SwiftData cache both use it. `AnalysisRecord(outcome:asset:revision:analyzedAt:)`
  maps a `FeaturePrintOutcome`: `.computed` → `analyzed` (vector), `.failed` → `failed` (no vector, current revision,
  photo's modification date), **`.skipped` → `nil`, never cached**: a skip is cheap to rediscover and can go away without
  the modification date changing (an iCloud-only original downloaded by Photos). Nothing writes `skipped` today.
- Data: `AnalysisSchemaV1` (`CachedAnalysis` `@Model`, flat, no relationships), `AnalysisMigrationPlan` (`stages: []`),
  internal `@ModelActor actor AnalysisStore`, `AnalysisContainerFactory`. The public `SwiftDataFeaturePrintCache` opens the
  store **lazily on first use**, off the main thread; `init(location:)` takes `.applicationSupport` (default),
  `.directory(URL)` or `.inMemory`.
- Upsert is explicit (fetch existing rows of a 200-ID chunk, update or insert, `save()`), not SwiftData's implicit
  unique-key upsert; duplicates in one call: last wins. Reads and purges fetch 500 IDs per query (SQLite variable limit).
  Each chunk runs in `autoreleasepool`. Rows with an unknown status or a byte count that is not a multiple of 4 are misses.
- Vectors are native `Float` bytes (`FeatureVectorPacking`), decoded by copying (misaligned `Data` slices are safe).
- Store: `Application Support/Analysis/Analysis.store`. The **directory** is excluded from backup (covers `-wal`/`-shm`
  and rebuilt files) and gets `.completeUntilFirstUserAuthentication`, which new files inherit; existing store files get it
  after opening (iOS only). `cloudKitDatabase: .none` is set explicitly: the default `.automatic` would sync through
  CloudKit if an iCloud entitlement were ever added.
- Open failure: log (`.private`), delete the store and its `-wal`/`-shm`, retry once; if that fails, an in-memory store for
  this launch; if even that fails, reads miss and writes throw `FeaturePrintCacheError.unavailable`. No crash path.
- No required-reason API is used (no file dates are read); the privacy manifest comment says so.
- Tests: `SwiftDataFeaturePrintCacheTests` (in-memory and temp-directory stores, `@testable` for the save count),
  `AnalysisRecordTests`, `MockFeaturePrintCacheTests`. **Device-only, still open:**
  `AnalysisCachePerformanceTests` (50k vectors read < 1.5 s on an iPhone 13, `RUN_DEVICE_PERFORMANCE_TESTS=1`); check its
  peak memory in Instruments (the `ModelContext` may keep fetched rows registered); confirm the store files' protection
  class on a device. The corrupt-store test assumes SwiftData throws on a non-SQLite file; it was first run in CI.
