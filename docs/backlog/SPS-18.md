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
