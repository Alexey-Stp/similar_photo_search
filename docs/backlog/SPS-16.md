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
