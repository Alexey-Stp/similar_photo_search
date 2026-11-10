# SPS-18 — Smart Selection use case

**Type:** User story · **Epic:** SPS-15 · **Depends on:** SPS-16, SPS-17

## User story

As a user, I want the app to suggest which photos to keep and which to delete in each group, so that I can clean up quickly
while still having the final say.

## Acceptance criteria

- **Given** a cluster, **then** the top-ranked member is marked **Keep (Best)**, and all others are pre-selected for deletion.
- **Given** a cluster member is a favorite, **then** it is never pre-selected. If several favorites exist, all are kept.
- **Given** two members' weighted quality scores (SPS-17, range 0…1) differ by at most 0.02, **then** both are kept, and the cluster is flagged "Review recommended".
- **Given** the cluster is an exact duplicate, **then** the version with higher resolution or edits is kept.
- The user can override any selection (SPS-21, SPS-22). Overrides persist for the session and survive a re-cluster if the members are unchanged.
- A global "Smart Select All" and "Deselect All" exist, and their result is shown before any deletion ("38 photos, 214 MB
  will be deleted"); the size comes from `PHAssetResource` `fileSize` via KVC, marked as an estimate.
- At least one photo per cluster is always kept; the selection model rejects an "all members selected" state unless the user explicitly confirms it.

## Technical notes

`SmartSelectionUseCase` (Domain) and `SelectionStore` (`@Observable @MainActor`, Presentation): `[clusterID: Set<assetID>]`.
`PHAssetResource.fileSize` is undocumented (KVC `value(forKey: "fileSize")`): optional, with a "size unavailable" fallback.

## Risks

Deleting a photo the user wanted is the worst possible outcome, so be conservative by default. The undocumented `fileSize` key may break.

## Implementation hints

- Input: `[SimilarityCluster]`, ranked members from SPS-17, `PhotoAsset` metadata.
- Rules: keep best; never select favorites; keep near-ties (`abs(a.score - b.score) <= 0.02` on the SPS-17 weighted score) and flag `needsReview`; exact duplicates keep
  highest pixel count, then edited; invariant: each cluster keeps ≥ 1 unselected member unless `confirmDeleteAll(clusterID)` was called.
- `SelectionStore`: `toggle(assetID, in:)`, `selectSmartAll()`, `deselectAll()`, `selectedCount`, `estimatedBytes` (async,
  off-main, optional), `isKept(assetID)`, overrides kept across re-cluster when member IDs are equal.
- Reads must be scoped per cell (fine-grained `@Observable` properties), or every thumbnail re-renders on each toggle (SPS-21).
- Tests: favorites never selected, tie handling, invariant enforcement, override preservation.
- From SPS-16: `SimilarityCluster` is immutable, with `id: String` (the newest member's ID, the same for the same members), `isExactDuplicate` and `averageDistance`; set `suggestedKeeperID` by creating a copy with the same `id`. Members arrive in library order (newest first), not ranked.
- From SPS-17: `QualityRanker.rank` gives `[RankedMember]` best first (`score` 0…1 within the cluster,
  `isProtected` for favorites, `reasons` as `QualityReason` string-catalog keys). Members whose measurement was skipped
  or failed are missing from it: never pre-select them. Take `pixelCount` and `isEdited` for the exact-duplicate rule
  from `QualitySignals`. Scores are min-max normalized, so in a two-photo cluster they differ by whole signal weights:
  the 0.02 near-tie mostly fires when the signals are equal or cancel out.

## Implementation notes

- **Domain:** `SmartSelectionUseCase.suggest(for:signals:)` (one cluster or many) takes the clusters and
  `[assetID: QualitySignals]` and runs `QualityRanker` itself, so callers don't pass a ranking. It returns
  `ClusterSelection` (`cluster` copied with `suggestedKeeperID` via `SimilarityCluster.withKeeper(_:)`, `ranking`,
  `suggestedForDeletion`, `needsReview`, `keptIDs`). Pure struct, built in `AppContainer`; nothing calls it yet (see SPS-21).
- **Rule details beyond the criteria** (all err on the side of keeping):
  - Near-tie is measured **against the keeper's score only** (not pairwise between any two members, which would keep
    two equally bad photos), with a `1e-9` slack so a difference of exactly 0.02 counts. Tolerance is
    `nearTieTolerance` (default `0.02`).
  - With no usable signal every score is 0, so everything is a near-tie: nothing is pre-selected, `needsReview`.
  - Members missing from the ranking (skipped/failed measurement) are kept and set `needsReview`. A cluster with no
    ranked member gets no keeper (`suggestedKeeperID == nil`) and nothing pre-selected.
  - **Exact duplicates skip the near-tie rule** (their scores almost always tie, which would keep every copy): keeper =
    most pixels, then edited, then best ranked; `needsReview` only for unranked members. Favorites are still kept.
  - Favorites are kept in addition to the keeper; the keeper is still the top-ranked member, favorite or not.
- **Presentation:** `SelectionStore` (`@Observable @MainActor`) holds one `ClusterSelectionState` object per cluster;
  cells must read `store.state(for: clusterID)` and call `isSelected(_:)` / `isKept(_:)` on it, so a toggle invalidates
  only that cluster (per cluster, not per thumbnail: clusters are small). `selectedCount` and `summary` are for bars.
  API: `upsert(_:)`, `remove(clusterIDs:)`, `toggle(_:in:) -> ToggleResult` (`.selected`, `.deselected`,
  `.needsConfirmation`, `.notFound`), `confirmDeleteAll(_:)`, `selectSmartAll()`, `deselectAll()`,
  `selectedAssetIDs`, `isKept(_:)`/`isSelected(_:)` by asset ID. `clusterIDs` keeps first-arrival order (append-only).
- **Overrides** are stored per cluster ID with the member set, only while the choice differs from the suggestion. They
  survive `remove` + `upsert` (rescan) when members are equal and are dropped for good when the members differ.
  `selectSmartAll()` forgets all overrides; `deselectAll()` records them, so a rescan does not reselect.
- **Invariant:** selecting the last kept member returns `.needsConfirmation` and changes nothing; `confirmDeleteAll`
  sets `isDeleteAllConfirmed`, which is cleared as soon as one member is kept again. A suggestion that selects every
  member is ignored (nothing selected).
- **Size:** `AssetSizeEstimator` (Domain protocol, `MockAssetSizeEstimator`); `PhotoKitAssetSizeEstimator` (Data,
  `actor`, batches of 200 in `autoreleasepool`) sums the KVC `fileSize` of **all** `PHAssetResource`s of a photo
  (original, edits, Live Photo video), reading the key only if the resource `responds(to:)` it, so a removed key gives
  "size unavailable", not a crash. The store asks only for selected photos with no known size and caches results for the
  session. `DeletionSummary.text`: "38 photos, about 214 MB will be deleted", "at least" when some sizes are missing,
  "(size unavailable)" when none is known, "Estimating size…" while pending. Not a required-reason API.
- `SelectionSummaryBar` (Smart Select All, Deselect All, summary) is a reusable bottom bar; SPS-21 adds the delete
  button. `ViewModelFactory` gained `var selectionStore: SelectionStore` (one per app session, from `AppContainer`).
- Strings: `selection.keepBest`, `selection.reviewRecommended` (for SPS-21/22 badges), `selection.smartSelectAll`,
  `selection.deselectAll`, `selection.summary*`.
- **Verified on Windows:** Domain tests (175, incl. 20 in `SmartSelectionUseCaseTests`, `-warnings-as-errors`), the
  three `scripts/check-*.sh`, and the 15 `SelectionStoreTests` that don't need the string catalog, built in a scratch
  package with the store sources. **Not run (need macOS CI):** the full Presentation tests (including
  `theSummaryTextNamesCountAndSize`, which checks the plural substitutions in the catalog), `PhotoKitAssetSizeEstimatorTests`
  (Data), the app build and SwiftLint. **Manual QA on a device:** the summary size is plausible against Settings ▸ Photos
  for a few known photos.
