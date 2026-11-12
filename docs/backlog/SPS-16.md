# SPS-16 — Similarity clustering engine

**Type:** Technical task · **Epic:** SPS-15 · **Depends on:** SPS-26

## Description

Pure Domain logic (no Apple frameworks except Accelerate). Input: **one shooting session** `[(id, creationDate, vector)]`.
Output: `[SimilarityCluster]` with 2 or more members.

Algorithm:

1. Input is one session from SPS-26, already sorted by `creationDate`. The engine never sees photos from different sessions.
2. Inside the session, a pair is compared only if the photos are at most `maxPairInterval` apart (default 60 min), so long
   sessions stay cheap. For typical sessions (≤ 50 photos) this is simply all pairs.
3. Edge if `distance ≤ threshold` (configurable; calibrated per feature-print revision on a labelled set; never hard-coded without a revision key).
4. Connected components with Union-Find (path compression plus union by rank).
5. Chaining guard: components larger than N (default 12) are re-clustered with complete linkage (every pair within
   `threshold × 1.15`) or split around medoids, to prevent A~B~C chains where A and C are dissimilar.
6. Optional fast path: exact duplicates (identical vectors or distance < ε) are flagged `isExactDuplicate`.

## Acceptance criteria

- Deterministic: the same input always gives the same clusters and order (stable sort by date, then id).
- Clusters of size 1 are discarded.
- Burst photos (same `burstIdentifier`) are grouped even if slightly over the threshold (threshold × 1.1).
- Vectors with different `revision` are never compared; mixed-revision input throws or is partitioned.
- Cost is per session: about O(s²), limited by `maxPairInterval`. A 500-photo session clusters in under 200 ms on an
  iPhone 13; a 20k-photo library split into sessions clusters in under 3 s in total.
- Unit tests cover: empty input; a single item; all-identical vectors (one cluster); a chain A–B–C split by the guard; a pair exactly `maxPairInterval` apart.
- Each cluster exposes `averageDistance` (confidence) for UI sorting.

## Technical notes

`struct ClusteringConfig: Sendable { threshold: Float; maxPairInterval: TimeInterval; maxChainSize: Int; burstSlack: Float }`.
The engine is synchronous and works on one session; parallelism and ordering belong to the coordinator (SPS-14).
`ClusteringEngine` protocol in Domain; the implementation contains no PhotoKit or Vision.

## Risks

The threshold is the single most important product parameter: ship it with locally tunable settings (Strict/Balanced/Relaxed)
and a calibration dataset in the repo. Chaining produces "why are these grouped?" moments. If `sessionGap` (SPS-26) is too
small, a real series is split and never compared.

## Implementation hints

- **Start from** the existing `ClusteringEngine` protocol, `SimilarityCluster` (`assetIDs`, `suggestedKeeperID`) and the
  `UnionFindClusteringEngine` placeholder (Data, SPS-2). Accelerate is allowed in the clustering engine only; decide whether
  the engine moves to Domain (as the ticket says) or stays in Data, and record it in the implementation notes.
- Input `struct VectorItem: Sendable { id: String; date: Date; burstID: String?; revision: Int; vector: [Float] }`
  (`revision` from `FeaturePrint.revision`). Items are partitioned by `revision` before any pair is compared, so items of
  different revisions never share a cluster; a test feeds identical vectors with two revisions and expects two clusters;
  `func clusters(in session: [VectorItem], config: ClusteringConfig) -> [SimilarityCluster]` (synchronous, pure).
- Two-pointer neighbour search limited to `maxPairInterval`; compare `vDSP.distanceSquared` against threshold² (no sqrt in
  the hot loop); burst pairs use `threshold * burstSlack`.
- Drop singletons, compute `averageDistance`, sort clusters by date descending.
- Tests (Swift Testing): empty, singleton, identical, chain splitting, `maxPairInterval` boundary, determinism (run twice).
  Performance test with a 500-item session of random 768-dim vectors.
- From SPS-26: `PhotoSession.assets` arrive newest first (`PhotoAsset.libraryOrder`), not oldest first; sort as needed and keep the determinism rule.
- From SPS-12: use `VectorMath.euclideanDistanceSquared` (Domain/Clustering, vDSP) for the hot loop; it is checked against Vision's `computeDistance`.

## Implementation notes

- **The engine lives in Domain**, not Data: `UnionFindClusteringEngine` is a stateless `struct` in
  `Domain/Clustering/` (the only Domain folder allowed to import Accelerate; it uses `VectorMath`, so it also builds and
  is tested on Linux/Windows). The Data placeholder was removed. `AppContainer` still constructs it; the
  `ClusteringEngine` protocol stays for mocks (`MockClusteringEngine`, now a lock-guarded class that records `calls` and
  can throw).
- **Contract:** `clusters(in: [VectorItem], config: ClusteringConfig) throws(ClusteringError) -> [SimilarityCluster]`,
  synchronous. `VectorItem(asset:featurePrint:)` builds an item (nil without a `creationDate` or for another photo's
  print). Items are deduplicated by ID and partitioned by **revision and vector length**; input order does not matter.
- **The threshold is keyed by revision** (`ClusteringConfig.thresholds: [Int: Float]`) and has **no default**: no
  labelled set exists yet, and a guessed number would be the single most important product parameter. A partition of
  two or more items whose revision has no threshold throws `ClusteringError.missingThreshold(revision:)`, so a missing
  calibration is never a silent "no duplicates found". The Strict / Balanced / Relaxed setting from the risks is not
  built: it needs calibrated values per revision first.
- Other parameters (defaults): `maxPairInterval` 60 min (inclusive), `maxChainSize` 12, `burstSlack` 1.1,
  `chainLinkageSlack` 1.15, `exactDuplicateDistance` 1e-4 (float noise only).
- **Chaining guard:** components larger than `maxChainSize` are re-clustered with agglomerative complete linkage (closest
  pair first, first pair in date/ID order on ties) while every pair stays within `chainLinkageSlack` × its threshold
  (× `burstSlack` too for burst pairs). Every pair counts there, also pairs further apart in time than
  `maxPairInterval`, so a long series of the same scene can be split. A component whose pairs are all within the slack
  is kept whole without agglomeration (O(k²)); otherwise it is O(k³) comparisons, acceptable for session-sized input.
- **`SimilarityCluster` changed:** `id` is now a `String` (default: the newest member's ID, unique within a scan and
  equal for equal input) instead of a random `UUID`, so results are deterministic and comparable. Added
  `averageDistance` (mean over all member pairs; only comparable within one revision) and `isExactDuplicate` (all pairs
  within `exactDuplicateDistance`). Members are in `PhotoAsset.libraryOrder`; clusters newest first, ties by ID.
- Performance tests (`ClusteringPerformanceTests`, 500-photo session < 200 ms, 20k library in sessions < 3 s) are
  device-only (`RUN_DEVICE_PERFORMANCE_TESTS=1`). On Windows, in a debug build without vDSP, the 500-photo session took
  1.06 s and the 20k library passed, so the numbers mean nothing until they run on a device.
- **Still open:** both performance tests on an iPhone 13 (now in [SPS-29](SPS-29.md)); the calibration spike (labelled
  fixture set → threshold for revision 2, now [SPS-28](SPS-28.md); then Strict / Balanced / Relaxed, no ticket yet);
  `swift test` for `Packages/Data` (the placeholder-conformance test changed), the app build and SwiftLint, which need
  macOS. Verified here: Domain tests on Windows (Swift 6.4.2, `-warnings-as-errors`), `check-domain-imports.sh`,
  `check-concrete-construction.sh`.
