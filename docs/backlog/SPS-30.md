# SPS-30 — Close guard-rail gaps: socket lint rule and script self-tests

**Type:** Technical task · **Epic:** SPS-27 · **Depends on:** SPS-5

## Description

Two gaps in the CI guard rails are documented but still open:

1. The SwiftLint zero-network rules don't match direct Darwin socket calls (SPS-5 acceptance criteria, open item in its
   implementation notes).
2. `scripts/check-domain-imports.sh` and `scripts/check-concrete-construction.sh` have no self-tests (root README,
   "Guard rails"). Every other guard is proven against fixtures.

## Acceptance criteria

- **Given** Swift source calling `socket(`, `connect(`, `getaddrinfo(` or `gethostbyname(`, **then** `swiftlint --strict`
  fails with a zero-network diagnostic.
- `scripts/fixtures/NetworkViolations.swift` has `// expect:` lines for each of these calls, plus lines that must **not**
  fire (for example a method named `connect(to:)` on a Swift type, or `socket` in a comment or string), and
  `check-swiftlint-fixture.sh` passes.
- **Given** a fixture Domain file that imports `Photos`, `UIKit`, `SwiftUI`, `SwiftData` or `Vision`, or imports
  `Accelerate` outside the clustering folder, **then** `check-domain-imports.sh` fails with the intended diagnostic
  (checked through `expect-failure.sh`).
- **Given** a fixture that constructs a concrete Data type outside `AppContainer`, **then**
  `check-concrete-construction.sh` fails with the intended diagnostic.
- CI runs the new self-tests next to the existing ones. The root README no longer says these scripts have no self-tests.

## Technical notes

Edit the SwiftLint rules on a machine with SwiftLint (macOS, or Windows with SwiftLint ≥ 0.64.0). Keep the fixtures
outside the paths the real checks scan, so they don't break the normal CI run.

## Implementation notes
