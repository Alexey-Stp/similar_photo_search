# SPS-4 — Privacy-focused onboarding flow

**Type:** User story · **Epic:** SPS-1 · **Depends on:** SPS-3

## User story

As a privacy-conscious user, I want to see clearly that my photos never leave my device, so that I feel safe granting full library access.

## Acceptance criteria

- The first launch shows a 3-page onboarding: (1) what the app does, (2) the "100% on-device, works in Airplane Mode"
  promise, (3) the permission primer with an "Allow Access" CTA, which triggers SPS-3.
- Onboarding is shown once; completion is stored in `@AppStorage("hasCompletedOnboarding")`.
- **Given** the user kills the app on page 2, **when** they relaunch, **then** onboarding restarts from page 1.
- **Given** permission was already granted (for example after a reinstall), **then** page 3's CTA reads "Continue" and skips the system prompt.
- Supports Dynamic Type up to AX5, VoiceOver labels on every element, Dark Mode and Reduce Motion (no page-transition animation).
- All strings are localizable through a String Catalog (`Localizable.xcstrings`).

## Technical notes

`TabView` with `.tabViewStyle(.page)`, `OnboardingViewModel`, SF Symbols (`lock.shield`, `iphone`, `airplane`). No remote images or fonts.

## Risks

Long localized strings at AX sizes can clip; wrap each page in a `ScrollView`.

## Implementation notes

- `OnboardingViewModel` keeps the current page in memory only, which is what makes "restart from page 1" work.
- `RootView` owns the `hasCompletedOnboarding` flag and passes completion in as a closure.
