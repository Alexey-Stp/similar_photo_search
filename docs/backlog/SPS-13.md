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
