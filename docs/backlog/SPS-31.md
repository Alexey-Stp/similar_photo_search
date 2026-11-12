# SPS-31 — Build and test with Xcode 26 and the iOS 26 SDK

**Type:** Technical task · **Epic:** SPS-27 · **Depends on:** SPS-2

## Description

Since 28 April 2026, App Store Connect only accepts builds made with Xcode 26 or later and the iOS 26 SDK. CI is
pinned to Xcode 16.4 (`XCODE_VERSION` in `.github/workflows/ci.yml`), so nothing it builds can ship, and the project
has never been built with Xcode 26. SPS-28's device run needs Xcode 26 as well: the calibration fixture leaves the
device only as a Swift Testing attachment, which needs Swift 6.2.

Move CI and the documented toolchain to Xcode 26, and make CI compile the test code that only builds for a physical
device. `CalibrationFixtureExtractionTests`, `QualityScoringDeviceTests` and part of `VisionFeaturePrintExtractorTests`
sit behind `#if os(iOS) && !targetEnvironment(simulator)`, and CI builds only for the Mac and the Simulator, so no
build has compiled them yet.

## Acceptance criteria

- CI selects an Xcode 26.x release (or later) on a runner image that ships it, and both jobs pass with the existing
  warnings-as-errors settings.
- A new CI step builds the app and every test target for a generic iOS device without signing
  (`xcodebuild build-for-testing -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`). **Given** a compile
  error in device-only test code, **then** CI fails. The `#if compiler(>=6.2)` branch of
  `CalibrationFixtureExtractionTests` is part of that build.
- New warnings are fixed at their source. Warnings stay errors (`Config/Shared.xcconfig`, the CI flags), and nothing
  is switched off to get a green build.
- No guard is weakened: the lint job and its self-tests are unchanged and pass; no new package, Info.plist key or
  required-reason API. The deployment target stays iOS 17.0, and iOS 26-only API goes behind `#available`.
- README (Requirements), CLAUDE.md (Stack, Commands) and the SPS-28 notes say Xcode 26 or later; "CI uses 16.4" and
  the separate "needs Xcode 26" note are gone.

## Technical notes

- No device needed: push, read the CI log, fix, repeat. Domain already builds with a newer Swift on Windows (SPS-16
  notes), so new diagnostics are most likely in `Packages/Data`, `Packages/Presentation` and the app target.
  `Config/Shared.xcconfig` makes warnings errors in the app target, so a local Xcode 26 build fails on them too.
- Keep Swift 6.2's opt-in modes off (default `MainActor` isolation, approachable concurrency): `SWIFT_VERSION`,
  `swift-tools-version` and the packages' Swift settings stay as they are. Adopting them is a separate decision.
- Built with the iOS 26 SDK, standard SwiftUI controls take the new system design. Look at every screen once in an
  iOS 26 Simulator; the full pass on a device is SPS-29.
- The "Pick iOS simulator" step prefers an "iPhone 16" and falls back to any iPhone. Check that the simulator named in
  the README and CLAUDE.md commands still exists in Xcode 26.
- Apple raises the minimum SDK every spring. Check Apple's "Upcoming requirements" page before an upload (SPS-32).

## Risks

Swift 6.2 and the iOS 26 SDK can surface real concurrency problems in the PhotoKit and Vision code, which take longer
than a version bump. Getting Xcode 26 may also need a different runner image (`runs-on`).

## Implementation notes
