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

- New SwiftLint rule `no_socket_calls`. It matches only the function name (`match_kinds: [identifier]`, so comments and
  strings never fire) for `socket`, `connect`, `getaddrinfo`, `gethostbyname`/`gethostbyname2`, `gethostbyaddr`,
  `getnameinfo`, `sendto` and `recvfrom`. It fires on free calls and `Darwin.`/`Glibc.`-qualified calls whose arguments
  are unlabelled and non-empty. Member calls (`publisher.connect()`), labelled calls (`connect(to: host)`) and
  `func`/`case` declarations don't fire, so a Swift method named `connect(to:)` stays legal. Not covered: `bind`,
  `listen` and `accept` (too generic to match by name) and `CFSocket*`.
- `check-domain-imports.sh` and `check-concrete-construction.sh` take an optional `[root]`, like `check-dependencies.sh`.
  Both now fail when the folders they scan are missing. Before, grep's exit 2 read as "no hits", so a wrong path passed silently.
  Hits are printed relative to the root, and the Accelerate exemption is anchored to `Packages/Domain/Sources/Domain/Clustering/`.
- `expect-failure.sh` accepts `--expect` more than once; every text must appear. Existing calls are unchanged.
- Fixtures: `scripts/fixtures/domain-imports-{forbidden,accelerate,allowed}` and
  `scripts/fixtures/concrete-construction-{violation,allowed}`, each a small repository tree outside the scanned paths.
- Not verified locally (no SwiftLint on the Windows machine): the real `swiftlint --strict` run and
  `check-swiftlint-fixture.sh`. The regex was checked against the fixture with Foundation's `NSRegularExpression` (ICU, the
  engine SwiftLint uses). Comments and strings were filtered by hand, so only CI proves the `match_kinds` filtering.
