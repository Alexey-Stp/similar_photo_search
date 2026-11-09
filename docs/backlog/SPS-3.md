# SPS-3 — Photo Library authorization flow (including Limited access)

**Type:** User story · **Epic:** SPS-1 · **Depends on:** SPS-2

## User story

As a user, I want to grant photo library access with a clear explanation, so that I understand why the app needs it and
what happens if I choose limited access.

## Acceptance criteria

- **Given** status `.notDetermined`, **when** the user taps "Allow Access", **then** the app calls
  `PHPhotoLibrary.requestAuthorization(for: .readWrite)` and routes based on the result.
- **Given** `.authorized`, **then** the user is taken to Home.
- **Given** `.limited`, **then** Home shows a persistent banner: "You've shared N photos. Results may be incomplete." It has
  a "Manage" action that calls `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)` and a "Settings" action.
- **Given** `.denied`, **then** a "Permission Denied" screen appears with a button that opens `UIApplication.openSettingsURLString`.
- **Given** `.restricted` (parental controls or MDM), **then** an explanatory screen appears with **no** Settings button.
- **Given** the user changes the permission in Settings and returns, **when** `scenePhase` becomes `.active`, **then** the
  status is re-read and the route updates without restarting the app.
- Edge case: the automatic iOS limited-library re-prompt is suppressed with `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES`.

## Technical notes

`PHPhotoLibrary.authorizationStatus(for: .readWrite)`, async `requestAuthorization(for:)`, Info.plist key
`NSPhotoLibraryUsageDescription`. `.readWrite` is required for deletion; `.addOnly` is not enough.
`presentLimitedLibraryPicker` needs a `UIViewController`; find the key window's top view controller.

## Risks

Calling `presentLimitedLibraryPicker` without a valid presenting view controller silently does nothing. The deprecated
non-`for:` `authorizationStatus()` returns `.authorized` for limited access.

## Implementation notes

- Domain type is `PhotoLibraryAuthorization` (the original prompt called it `PhotoAccessLevel`); service protocol
  `PhotoPermissionService` also has `accessiblePhotoCount()` for the banner.
- `PermissionViewModel` (Presentation/Root) owns the status and decides the route via `AppRoute`; `RootView` refreshes on launch and on `.active`.
- A newer refresh always wins over a slower older one (request IDs), so the banner never shows a stale count.
