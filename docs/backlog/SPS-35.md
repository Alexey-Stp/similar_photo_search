# SPS-35 — Photo-first redesign: Home, groups, comparison, deletion and app icon

**Type:** Story · **Epic:** SPS-19 · **Depends on:** SPS-20, SPS-21, SPS-22, SPS-25

## Description

The first UI used stock iOS controls throughout: grey cards, system-blue buttons, default text styles. It works but
looks generic, and some of the stock colour pairs miss WCAG AA in Light mode. This ticket gives the app a modern,
photo-first look that follows iOS 26 (Liquid Glass bars, rounded display type, black/white "ink" buttons) and adds
review features users asked for: sizes everywhere, the groups on Home, a full photo grid per group, deleting one photo
right away, and starting a review over.

The visual reference is the "SimilarPhotos Redesign" design canvas (Home, Scanning, Groups, Compare, Review Deletion,
Onboarding, App icon). The tokens and component rules are in the "SimilarPhotos" design system page. Both are private
claude.ai artifacts of the project owner.

## Acceptance criteria

### Look

- Primary actions on Home, onboarding and the permission screens are full-width ink pills (label colour on the
  background colour, 21:1 in both appearances) that grow with Dynamic Type.
- Headings and large figures use the rounded system design; changing numbers use monospaced digits.
- Cards use 28 pt continuous corners. Bars that float over content (selection bar, comparison top bar and filmstrip)
  use Liquid Glass on iOS 26 and the regular material before it.
- Destructive buttons use Apple's accessible red (#d70015) with white text (5.4:1). Status colours sit on icons and
  fills, never on text: the Best badge is black on green, chips and notices tint only their icon.
- Full-screen messages (onboarding, access denied, access restricted) show their symbol in a large circle.

### Home

- The results card leads with the size that can be freed as a large figure, then tiles for groups, photos and the
  **total size of all photos in groups**. Sizes are formatted in bytes, KB, MB or GB for the locale.
- **Start Over** asks "Start over?", then clears the stored results, the groups shown and every keep/delete choice, and
  runs a full scan. It deletes no photo.
- The groups found are listed under the summary card, with **See All** opening the group list. Photos can be toggled
  there; selecting a group's last kept photo asks "Delete every photo of this group?" as in the list.
- The scanning card shows a larger progress ring with the percentage in rounded type.

### Groups

- Filters are a row of pills (All Groups, Needs Review, Exact Duplicates); the toolbar menu only sorts.
- Each group card shows **every photo** in a grid that fills the card width, the suggested keeper first.
- Each card shows the group's **total size** ("4 photos · 18 MB") and, when photos are selected, the **size to delete**
  ("12 MB to delete").
- The selection bar floats at the bottom with the summary, Smart Select All, Deselect All and a short "Delete" button;
  VoiceOver reads the full "Delete 38 photos (214 MB)".

### Comparison

- Close, the position and the side-by-side switch float over the full-height photo; the filmstrip is a glass strip.
- The info panel is a rounded dark sheet: "Keep This One" (ink pill), **Mark for Deletion** / Keep, Mark as Best and
  **Delete Now**. Delete Now deletes the shown photo through the usual review sheet and the system alert.

### Deletion review

- Shows the size as a large figure, the counts, every photo in a grid, the Recently Deleted note and a red
  "Delete N Photos" button with a line that iOS asks to confirm.

### App icon

- `AppIcon.appiconset` has a 1024 × 1024 opaque icon: two photos of the same face, eyes closed marked with a red cross,
  smiling marked with a green check. Its source is `docs/design/app-icon.svg`.

### Quality

- VoiceOver labels, hints and traits are kept or added for every changed control; icon-only buttons use their title
  as the label. Layouts switch to stacks at accessibility text sizes.
- All new strings are in `Localizable.xcstrings`.
- Presentation tests pass and `swiftlint --strict` is clean.

## Technical notes

- No Domain or Data changes: the redesign and the new features live in `Packages/Presentation`.
- Never delete without the user's explicit action (CLAUDE.md rule 2): Start Over deletes nothing; Delete Now goes
  through the review sheet and the system alert like bulk deletion.

## Implementation notes

Implemented on branch `SPS-35` and merged through its pull request. The look was **not** checked on a device or in the
Simulator: the Simulator's Vision finds no groups in test photos, so the group screens could not be reached there.
Verified by the Presentation tests (178 passing), `swiftlint --strict` and a full app build.

- **Shared styles.** `HomeInkButtonStyle`, `HomeHeroNumber`, `HomeStatTile`, `HomeStartOverButton` and
  `HomePrivacyFooter` are in `Home/HomeStyle.swift`; the ink button is also used on onboarding, the permission screen
  and the comparison panel. `View.glassBackground(in:)`, `GlassCircleButtonStyle` and `GlassCircleToggleStyle` are in
  `Components/GlassBackground.swift`; `HeroSymbol` is in `Components/HeroSymbol.swift`.
- **Sizes.** `ClusterListViewModel` already estimated every member's size for the size sort. Those sizes now drive the
  UI: `sizesRevision` (observable) changes when sizes arrive, `sizes(of:)` and `allGroupsSizes` return `GroupSizes`
  (total, selected, complete), and `ClusterCardModel` carries `photoSizes` and `sizesComplete`. `SelectionStore` still
  estimates only selected photos for the deletion summary, so its tests are unchanged.
- **Start Over.** `HomeViewModel.startOver()` removes every stored session result through
  `ClusterRepository.apply(upserted:removedSessionIDs:)`, calls `ScanViewModel.clearResults()` (which calls the new
  `SelectionStore.reset()`, forgetting overrides too) and starts a non-silent scan. Each scan reads stored results
  afresh (`ScanRun`), so the new scan recomputes every session from cached feature prints. Covered by
  `HomeStartOverTests`.
- **Shared group rows.** `ClusterCardRow` and `View.deleteAllConfirmation(_:isActive:)` are used by both the group list
  and Home. On Home the dialog is active only while Home is on top (no pushed list, no comparison), so it never shows twice.
- **Thumbnails.** `ClusterListViewModel.thumbnailSide` went from 88 to 112 pt so grid tiles stay sharp; the prefetch
  test now derives its size from the constant.
- **Delete Now.** `PhotoComparisonViewModel.deleteNow(_:)` sets `deleteNowRequest`; the comparison screen presents
  `DeletionSheet` for that one photo. The old "Delete" button (which only marks) is now labelled "Mark for Deletion".
- **Contrast fixes** made earlier on the same branch: Best badge text black, chip and notice words in `.primary`, the
  error card's message no longer red text.

Open:

- Check every changed screen on a device in Light, Dark and at AX5 (SPS-29).
- The design system page still describes the stock blue buttons; update it to the ink pills, glass bars and sizes.
- Not built from the mockups: the "Latest groups" thumbnail stacks on Home (the full group list is shown instead), the
  storage bar and a "need review" tile.
- The app icon has no custom dark or tinted variant; iOS derives them.
