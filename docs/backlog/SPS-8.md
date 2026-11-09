# SPS-8 — Album and scope selection UI

**Type:** User story · **Epic:** SPS-6 · **Depends on:** SPS-7

## User story

As a user, I want to choose which albums or time range to scan, so that I can clean a specific trip or event quickly without scanning everything.

## Acceptance criteria

- **Given** Home, **when** the user taps "Scan scope", **then** a sheet lists "All Photos", smart albums and user albums with their estimated counts.
- The user can multi-select albums. An asset that sits in several selected albums is processed once (deduplicated by `localIdentifier`).
- There is a date-range filter with presets: Last 30 days, This year, Custom.
- A "Skip screenshots" toggle exists and defaults to on.
- **Given** a selected album is deleted outside the app, **when** the sheet reopens, **then** the album is silently removed from the selection.
- Scope is persisted between launches (album IDs stored; IDs that no longer exist are dropped).

## Technical notes

`ScopeSelectionViewModel` (`@Observable`), scope persisted as `Codable`. Uses `PhotoLibraryRepository.albums()`.
Footer with an estimated photo count, debounced 300 ms (cancel the previous task).

## Risks

Smart-album counts (`estimatedAssetCount`) can be `NSNotFound`, so fall back to a fetch count. Computing counts for hundreds
of albums on the main thread causes UI lag.

## Implementation notes

- What is saved is `ScopePreferences` (Domain), not `ScanScope`: the date filter is stored as a preset (`DateFilter`:
  any time, last 30 days, this year, custom), so "Last 30 days" stays current. `scanScope(now:calendar:)` resolves it
  right before a scan (SPS-14, SPS-20).
- Persistence goes through the `ScopePreferencesStore` protocol; `UserDefaultsScopePreferencesStore` (Data) keeps JSON under
  the `scanScope` key (UserDefaults CA92.1 is already in the privacy manifest). Unreadable data falls back to the default scope.
- No selected album means All Photos (`albumIDs == nil`). The Recents smart album is not listed, because it is the whole library.
- Stale album IDs are dropped every time the sheet opens, and the cleaned scope is saved at once. If every selected album is
  gone, the scope falls back to All Photos.
- Deduplication across albums is done by the repository (SPS-7). The footer count is the per-album sum, an upper bound, so it reads "About N photos".
- `includeBursts` has no UI yet; its saved value is kept.
- Under limited access, saved album IDs that aren't listed are kept (not dropped): PhotoKit can't tell a hidden album from a
  deleted one there. Only full access drops them. "All Photos" clears them.
- A saved custom range is used exactly as saved until the user edits its days, so opening the sheet in another time zone
  doesn't shift it. Loading re-saves the scope only when album IDs were dropped or de-duplicated.
- A custom range ends at the last instant before the next day starts (`nextDown`), so photos with fractional-second
  timestamps late on the last day are included. "This year" always starts on January 1 (Gregorian), whatever calendar is set.
