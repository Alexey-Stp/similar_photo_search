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

## Implementation notes

- **Where things live.** `HomeViewModel` (Presentation/Home, one per app session, `factory.homeViewModel`, built in
  `AppContainer`) derives `ViewState` (`idle`, `scanning(ScanProgress, foundSoFar:)`, `results(HomeSummary)`, `empty`,
  `error(String)`) from `ScanViewModel` + `SelectionStore`; `isLimitedAccess` stays on `PermissionViewModel`.
  `HomeDashboard` (in `Screens/HomeView.swift`) replaces `ScanStatusSection`, which is deleted. Typed routes:
  `HomeRoute` has only `.clusters`; scope stays the SPS-8 sheet and there is no settings screen yet.
- **Launch.** `launch()` (once per session) loads `ClusterRepository.storedResults()`, turns them into
  `ClusterSelection(unsuggested:)` (nothing pre-selected, no keeper) via `StoredSessionResult.launchSelections(from:)`
  (Domain): sessions newest first by the date encoded in the session ID (`PhotoSession.newestDate(fromID:)`), so the
  file format is unchanged. Then it starts a **silent** scan, which re-publishes the same IDs with a suggestion
  (replaced in place). Stale results (other `resultsKey`) are shown too; the scan sends `.removed` for them.
  "A previous scan exists" = stored results were non-empty, or a scan of this session reached `.done`
  (`ScanViewModel.hasCompletedScan`). A library with only single-photo sessions stores nothing, so it launches idle.
- **Silent vs full scan.** Silent (results stay, `ScanProgressBar` above them): the launch scan, library changes,
  pull-to-refresh once a previous scan exists. Full scanning state: Start Scan, Scan Again, Try Again, and
  pull-to-refresh before any scan. Pull-to-refresh returns as soon as the scan has started and does nothing while one runs.
- **Library changes.** Home consumes `LibraryChangeObserving.changes()`. Each event, only after a previous scan,
  starts a silent scan; during a scan it queues one for right after (`ScanViewModel.onScanEnded`); in the background
  it waits for `.active`. The app's own deletions (SPS-25) will trigger this too.
- **Error state** wins over results once a scan failed (on a device today: always, `missingThreshold`); the error card
  still offers "Review" for the groups found before.
- **Summary.** Photo count = members of all groups. "Can be freed" = `SelectionStore.summary` of the photos currently
  selected (hidden while nothing is selected or sizes are being estimated), so cached groups at launch show no size
  until the rescan suggests. Skipped line: "N photos skipped (stored only in iCloud)" when every skip is iCloud-only,
  otherwise "N photos skipped"; the sheet lists every `SkipReason` with an explanation and the no-network footer.
- **Accessibility.** Progress is announced through `ScanViewModel.accessibilityProgressText`, which moves in 10 %
  steps (rate limit); the counters have `.updatesFrequently`.
- **Idle timer.** `scanScreenAppeared/Disappeared` are now counted, because Home and the group list overlap during a push.
- **Banner count.** `PermissionViewModel` takes a `PhotoLibraryRepository` and counts
  `ScanScope(excludeScreenshots: false)`; `PhotoPermissionService.accessiblePhotoCount()` was removed (protocol,
  PhotoKit implementation, mock).
- **Interim group list.** `ClusterListScreen` (Home/) shows a text row per group, `ScanProgressBar` pinned at the top
  while any scan runs, and `SelectionSummaryBar` at the bottom. SPS-21 replaces the rows.
- **Verified on Windows:** Domain tests (210, incl. `StoredResultsLaunchTests`, `MockLibraryChangeObserverTests`),
  `-warnings-as-errors`; `check-domain-imports.sh`, `check-concrete-construction.sh`, `check-privacy-manifest.sh`.
  The view models compiled in a scratch package against a `ScenePhase` stub, where `HomeViewModelTests`,
  `ScanViewModelTests` and `HomeSummaryTests` passed. **Not run (need macOS CI):** the real Presentation build and
  tests, the views and previews, `Packages/Data` tests, the app build, SwiftLint.
- **Manual QA still open (device):** relaunch shows the last groups at once and the bar updates them; pull-to-refresh;
  an external change in Photos triggers a rescan; Review Now during a scan keeps the bar at the top of the list;
  skipped sheet with iCloud-only photos ("Optimize iPhone Storage"); VoiceOver reads the progress at most every 10 %;
  AX5 Dynamic Type and Dark Mode on every state; limited-access banner count matches the shared photos.
