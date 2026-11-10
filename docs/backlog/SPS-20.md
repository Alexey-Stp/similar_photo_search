# SPS-20 — Home / scan dashboard

**Type:** User story · **Epic:** SPS-19 · **Depends on:** SPS-14

## User story

As a user, I want a home screen that shows scan status and the space I can free up, so that I know what to do next.

## Acceptance criteria

- States: `idle` (never scanned, "Start Scan"), `scanning` (progress ring, processed/total, ETA, Cancel), `results` (N groups,
  M photos, ~X MB reclaimable, "Review"), `empty` ("No similar photos found"), `error`, and the limited-access banner (SPS-3).
- The skipped-items summary is tappable: "128 photos skipped (stored only in iCloud)", with an explanation that the app does not download from the network.
- **Given** a previous scan exists, **when** the app launches, **then** cached clusters appear immediately, and an incremental re-scan runs silently.
- Pull-to-refresh starts an incremental scan.
- **Given** a scan is running, **when** the first groups are found, **then** the scanning state shows a live counter
  ("12 groups found so far") and a "Review now" button that opens the group list while the scan continues.
- **Given** the user is reviewing during a scan, **then** a compact progress bar stays visible at the top of the group list.

## Technical notes

`HomeViewModel` with `enum ViewState`, `NavigationStack` with typed routes, `Gauge` or a custom ring, `.refreshable`.
Home already has the "Scan Scope" toolbar button and sheet (SPS-8); the scan uses `ScopePreferences.scanScope(now:calendar:)`.
Switch the limited-access banner count to the repository count (left over from SPS-7).

## Risks

Progress updates arriving too often cause re-render spam; honour the SPS-14 throttling.

## Implementation hints

- Inputs: `ScanProgress` and `ClusterUpdate` streams, cached clusters from a `ClusterRepository`, `PhotoLibraryAuthorization`.
- `ViewState`: idle, scanning(ScanProgress, foundSoFar: Int), results(Summary), empty, error(String); a separate `isLimitedAccess` flag.
  Summary: groupCount, photoCount, estimatedBytes?, skipped breakdown.
- Routes: `.clusters`, `.settings`, `.scope`. `ByteCountFormatter` for sizes.
- Accessibility: progress announced via `.accessibilityValue`, rate-limited.
- `#Preview`s for every state with mock data.
- From SPS-14: `factory.scanViewModel` (one per app session) drives the scan (`startScan`, `cancelScan`, `progress`, `etaText`, `isPausedToCoolDown`, `isSlowedByLowPowerMode`, `errorText`, `groupCount`); `ScanStatusSection` is the stopgap UI to replace. Cached clusters at launch: `ClusterRepository.storedResults()` (clusters only, no suggestion; the next scan re-publishes them with suggestions under the same IDs). Skipped breakdown: `ScanProgress.skipped`. Nothing consumes `LibraryChangeObserving.changes()` yet: run `startScan()` on each event while Home is in the foreground. Until the threshold is calibrated every device scan ends in `.failed(.missingThreshold)`.
