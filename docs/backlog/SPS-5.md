# SPS-5 — Zero-network policy and privacy manifest

**Type:** Technical task · **Epic:** SPS-1 · **Depends on:** SPS-2

## Description

Guarantee the "no data leaves the device" requirement through tooling, not only code review. Add `PrivacyInfo.xcprivacy`,
declare the required-reason APIs, and set `NSPrivacyTracking = false`. Add a CI check that fails if forbidden symbols appear in the sources.

## Acceptance criteria

- CI fails if the sources contain `URLSession`, `URLRequest`, `NWConnection`, `WKWebView`, `isNetworkAccessAllowed = true`
  or any remote SPM dependency outside an allow-list.
- The privacy manifest validates in an Xcode archive with no warnings in the privacy report.
- Manual QA: a full scan, analysis and deletion in **Airplane Mode** behave the same as online.
- Manual QA: Instruments' Network profiler (or a proxy) shows zero outbound connections during a full scan.

## Risks

Apple frameworks may make network calls themselves (for example iCloud Photos sync); the privacy copy says "this app does
not transmit". iCloud-only originals are skipped, never downloaded (SPS-9).

## Implementation notes

- Guard rails: SwiftLint `custom_rules` in `.swiftlint.yml` (with a line-by-line fixture), `scripts/check-privacy-manifest.sh`
  (required-reason APIs from `scripts/required-reason-apis.txt`), `check-dependencies.sh`, `check-entitlements.sh`, `check-info-plist.sh`.
- Using a new required-reason API (UserDefaults, file timestamps, disk space, boot time) means adding its entry to the manifest; CI asks for it.
- The manual checks are in [docs/qa/zero-network.md](../qa/zero-network.md). They must be re-run as part of SPS-14, SPS-24 and SPS-25.
