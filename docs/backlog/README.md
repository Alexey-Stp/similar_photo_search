# SimilarPhotos backlog

Native iOS app (Swift + SwiftUI) that finds and deletes near-duplicate photos.
All processing is strictly on-device, with zero network data transmission.

One file per ticket lives next to this index (`SPS-<n>.md`). To work on a ticket, read **this page** (principles and
dependencies) and **the ticket file**. Other ticket files only as the `/ticket` skill allows: the implementation notes of its
dependencies, and a dependent ticket right before adding a line to it. The ticket's acceptance criteria are its definition of done.

How the files relate to the rest of the repo:

- [CLAUDE.md](../../CLAUDE.md) holds the project-wide rules (zero network, memory, concurrency, architecture). It replaces the
  old "shared AI context preamble", so ticket files don't repeat it.
- The code is the truth for names and types. The "Implementation hints" in ticket files were written before the code existed;
  if a hint names a type differently from what is already in `Packages/` (for example `PhotoAccessLevel` vs
  `PhotoLibraryAuthorization`, `FeatureVector` vs `FeaturePrint`), use and extend the existing type.
- When a ticket is finished, its file gets an **Implementation notes** section (decisions and deviations a later ticket must
  know), and its row below is set to Done. Use the `/ticket` skill, which does this as part of the workflow.

## Core product principles

1. **Similar photos are taken close together in time.** Two photos are compared only if they belong to the same *shooting
   session*: a run of photos where every gap between neighbouring shots is at most `sessionGap` (default 15 min,
   configurable). Photos from different days are never compared. Consequences:
   - Comparison cost drops from "the whole library" to small sessions, usually 2–50 photos.
   - A photo that is alone in its session needs **no Vision analysis at all**; it is skipped before its image is even loaded.
   - Clusters never need merging across sessions, and an incremental rescan only touches the sessions that changed.
2. **Show results while scanning.** The library is processed session by session, newest first. As soon as a session is
   analysed, its groups appear in the UI, and the user can review and delete them while the rest of the library is still being scanned.

**Accepted trade-off:** copies of the same picture saved on different days (forwarded from messengers, re-downloaded,
re-imported) are not found. If needed later, this can be a separate "exact copies across the library" feature based on file hashes.

## Tickets

Status: **Done** (merged), **Review** (implemented, PR open or pending), **To do**.

### Epic SPS-1 — Project setup, permissions and onboarding

Set up the Xcode project, module layout, CI and privacy guardrails; the permission flow for every authorization state; a
welcome screen that explains the on-device-only promise.
**Done when:** the app builds and runs on a device through CI with tests passing; all `PHAuthorizationStatus` values are
handled in the UI; the privacy manifest is present and the App Store label can honestly read "Data Not Collected".
**Risk:** badly handled Limited access makes the app look broken ("no duplicates found"); an unexplained permission prompt leads to high denial rates.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-2](SPS-2.md) | Bootstrap project structure, Clean Architecture modules and DI container | Done | — |
| [SPS-3](SPS-3.md) | Photo Library authorization flow (including Limited access) | Done | SPS-2 |
| [SPS-4](SPS-4.md) | Privacy-focused onboarding flow | Done | SPS-3 |
| [SPS-5](SPS-5.md) | Zero-network policy and privacy manifest | Done | SPS-2 |

### Epic SPS-6 — Gallery scanning and asset extraction

Fetch image assets efficiently and in strict date order, split them into shooting sessions, let the user narrow the scope,
and stream downscaled pixel data to analysis in memory-bounded batches. Track library changes between runs.
**Done when:** 50,000 photos are enumerated in under 2 s without pixel data; image loading stays under 250 MB peak on an
iPhone 12; library changes are picked up incrementally.
**Risk:** OOM from image decoding, iCloud-only assets, libraries with more than 100k assets.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-7](SPS-7.md) | `PhotoLibraryRepository` with scope filters | Done | SPS-2 |
| [SPS-8](SPS-8.md) | Album and scope selection UI | Done | SPS-7 |
| [SPS-26](SPS-26.md) | Split the library into shooting sessions by time | Done | SPS-7 |
| [SPS-9](SPS-9.md) | Memory-safe batched image loading pipeline | Done | SPS-7 |
| [SPS-10](SPS-10.md) | Incremental library change tracking | Done | SPS-13, SPS-26 |

### Epic SPS-11 — Visual analysis and caching

Feature prints with `VNGenerateImageFeaturePrintRequest`, vectors cached in SwiftData, analysis as a cancellable,
resumable, thermally-aware background job.
**Done when:** first run ≥ 25 images/s on an iPhone 13 (counting only photos that need analysis); first groups on screen
within 5 s on a 10k library; second launch with an unchanged library reaches clusters in under 3 s; the scan survives app kill and resumes.
**Risk:** feature-print revision mismatch after an iOS update; the Simulator gives slow or different Vision results; thermal throttling.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-12](SPS-12.md) | Feature print extraction via Vision | Done | SPS-9 |
| [SPS-13](SPS-13.md) | SwiftData feature print cache | Done | SPS-12 |
| [SPS-14](SPS-14.md) | Analysis orchestrator: progress, cancellation, resume, thermal | Done | SPS-9, SPS-12, SPS-13, SPS-16, SPS-26 (SPS-10, SPS-17 when available) |

### Epic SPS-15 — Clustering and smart selection

Group near-duplicates by feature-print distance inside one shooting session; rank by quality; pre-select all but the best.
**Done when:** on a labelled set of ≥ 500 photos, precision ≥ 95% and recall ≥ 80%; clustering 20k vectors takes under 5 s on an iPhone 13.
**Risk:** threshold tuning; session gap too small splits real series; transitive chaining; picking the wrong "best" photo erodes trust.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-16](SPS-16.md) | Similarity clustering engine | Done | SPS-26 |
| [SPS-17](SPS-17.md) | Photo quality scoring | Done | SPS-9 |
| [SPS-18](SPS-18.md) | Smart Selection use case | Done | SPS-16, SPS-17 |

### Epic SPS-19 — User interface

Home/scan dashboard, cluster list, comparison, review and delete. Smooth scrolling with thousands of thumbnails.
**Done when:** no hitches in Instruments while scrolling 1,000 clusters on an iPhone 12; new groups appear while the scan runs
and the list never jumps under the user's finger; full VoiceOver, Dark Mode and Dynamic Type.
**Risk:** thumbnail memory pressure, main-thread image decoding, selection re-render storms.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-20](SPS-20.md) | Home / scan dashboard | Review | SPS-14 |
| [SPS-21](SPS-21.md) | Cluster list with efficient thumbnail loading | To do | SPS-18, SPS-20 |
| [SPS-22](SPS-22.md) | Photo comparison screen | To do | SPS-18, SPS-21 |

### Epic SPS-23 — Deletion

Delete confirmed assets through `PHAssetChangeRequest.deleteAssets`; handle the system alert, user cancellation, partial
failures and non-deletable assets; keep cache and UI consistent.
**Done when:** deletion works for 1 to 2,000 photos; user cancellation is never shown as an error; cache and clusters are
consistent after every outcome; users are told photos go to Recently Deleted for 30 days.
**Risk:** the system alert can't be customized or skipped; shared-library assets may not be deletable; very large batches may hit system limits.

| Ticket | Title | Status | Depends on |
|---|---|---|---|
| [SPS-24](SPS-24.md) | `AssetDeletionService` via PhotoKit change requests | To do | SPS-2 |
| [SPS-25](SPS-25.md) | Deletion confirmation flow, results and post-deletion sync | To do | SPS-18, SPS-21, SPS-24 |

## Suggested order

| Sprint | Tickets |
|---|---|
| 1 | ~~SPS-2, SPS-5, SPS-3, SPS-4, SPS-7~~ |
| 2 | SPS-8, SPS-26, SPS-9, SPS-12, SPS-13, spike: threshold and session-gap calibration on a labelled dataset |
| 3 | SPS-14, SPS-16, SPS-10 |
| 4 | SPS-17, SPS-18, SPS-20, SPS-21 |
| 5 | SPS-22, SPS-24, SPS-25, hardening (performance and accessibility passes) |

**Biggest cross-cutting risks:** the similarity threshold (SPS-16) and the session gap (SPS-26). Make a labelled set of
about 500 photos with "same / not same" pairs early in sprint 2, store it in the repo as a test fixture, and use it as a
regression test for every change to clustering or the feature-print revision.
