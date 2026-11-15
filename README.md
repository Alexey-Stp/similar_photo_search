# SimilarPhotos

A native iOS app that finds near-duplicate photos in your library and helps you delete them.
Everything runs **on device**: the app makes no network calls, and photos that exist only in iCloud are skipped rather than downloaded.

> Status: the feature tickets SPS-2 to SPS-26 in the [backlog](docs/backlog/README.md) are implemented, and the guard-rail
> gaps are closed ([SPS-30](docs/backlog/SPS-30.md)). Not yet usable on a device: the similarity threshold is not
> calibrated, so every scan stops with "not calibrated". The calibration tooling is merged; the labelled set and the
> threshold need a physical iPhone ([SPS-28](docs/backlog/SPS-28.md)). Still open before the first App Store release:
> device QA ([SPS-29](docs/backlog/SPS-29.md)) and the submission ([SPS-32](docs/backlog/SPS-32.md)).

## Requirements

- macOS with Xcode 26 or later (iOS 26 SDK, Swift 6.2). App Store Connect accepts only builds made with it.
- iOS 17.0+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint)

```bash
brew install xcodegen swiftlint
```

## Getting started

The Xcode project is generated from [project.yml](project.yml) and is not committed.

```bash
xcodegen generate
open SimilarPhotos.xcodeproj
```

Re-run `xcodegen generate` after adding or removing files or changing `project.yml`.

## Build & test

```bash
# app + all package tests on a simulator
xcodebuild test -project SimilarPhotos.xcodeproj -scheme SimilarPhotos \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# package tests only (fast, macOS host)
swift test --package-path Packages/Domain
swift test --package-path Packages/Data

# lint
swiftlint --strict
```

Vision feature prints and performance numbers must be checked on a **physical device**. The Simulator gives different results.

## Architecture

Clean Architecture + MVVM, split into three local Swift packages plus the app target:

| Module | Contents | May depend on |
|---|---|---|
| `Packages/Domain` | Entities, service protocols, `DomainTestSupport` mocks | Foundation only |
| `Packages/Data` (module `DataLayer`) | PhotoKit, Vision and SwiftData implementations | Domain |
| `Packages/Presentation` | SwiftUI views, `@Observable @MainActor` view models | Domain |
| `SimilarPhotos/` | `@main` app, `AppContainer` (composition root), Info.plist, privacy manifest | all of the above |

- `AppContainer` is the **only** place concrete Data types are created. It is injected into SwiftUI with `.environment(\.viewModelFactory, container)`.
- Services are `actor`s and pass `localIdentifier` strings or `Sendable` structs, never `PHAsset`.
- Swift 6 language mode, strict concurrency `complete`, warnings are errors.

## Guard rails

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs these on every pull request and on pushes to `main`,
unless the change is docs-only (see below):

| Check | Script |
|---|---|
| Domain imports only Foundation (Accelerate only in clustering) | [scripts/check-domain-imports.sh](scripts/check-domain-imports.sh) |
| Concrete Data types only in `AppContainer` | [scripts/check-concrete-construction.sh](scripts/check-concrete-construction.sh) |
| Remote packages only from [allowed-packages.txt](allowed-packages.txt): `Package.swift`, `project.yml` and every `Package.resolved` (transitive packages too) | [scripts/check-dependencies.sh](scripts/check-dependencies.sh) |
| Required Info.plist usage keys present; no network keys (ATS, local network, Bonjour, background fetch/push) | [scripts/check-info-plist.sh](scripts/check-info-plist.sh) |
| No networking entitlements in any `*.entitlements` file or configured entitlements path | [scripts/check-entitlements.sh](scripts/check-entitlements.sh) |
| Privacy manifest: no tracking, no collected data, every entry well-formed, and every required-reason API used in the Swift/C/Objective-C sources is declared | [scripts/check-privacy-manifest.sh](scripts/check-privacy-manifest.sh) + [scripts/required-reason-apis.txt](scripts/required-reason-apis.txt) |
| No networking APIs or frameworks, no direct socket or DNS calls (`socket(`, `connect(`, `getaddrinfo(`, `gethostbyname(`, ...), no remote URL literals. `isNetworkAccessAllowed` may only be written as `= false`, followed by nothing but end of line, `;`, `}` or a `//` comment. Anything after a block comment, `toggle()`, `inout` (`&`) and key paths are rejected. | SwiftLint custom rules in [.swiftlint.yml](.swiftlint.yml) |

**Self-tests.** Every guard (Domain imports, composition root, Info.plist, entitlements, privacy manifest, dependencies, SwiftLint rules) also runs against fixtures in [scripts/fixtures/](scripts/fixtures/):

- Each negative fixture must be rejected **with the intended diagnostic** ([scripts/expect-failure.sh](scripts/expect-failure.sh)).
- The SwiftLint rules are checked line by line against `// expect:` annotations, including lines that must *not* fire ([scripts/check-swiftlint-fixture.sh](scripts/check-swiftlint-fixture.sh)).
- The Domain import, composition root and dependency checks take an optional root folder, so their fixtures are small
  repository trees (for example `scripts/fixtures/domain-imports-forbidden/Packages/Domain/...`). The first two treat a
  root without the expected folders as an error, never as a pass.

When you change a rule, keep its fixture in sync. Fixtures live outside the paths the real checks and SwiftLint scan.

After the guards, CI builds the app and runs `DomainTests`, `DataTests` and `PresentationTests`.

**Docs-only changes** skip both macOS jobs: when every changed file is under `.claude/` or `docs/`, or is a Markdown
file at the repository root, [scripts/ci-needs-build.sh](scripts/ci-needs-build.sh) tells CI to skip lint, build and
tests. Anything else runs everything, and so do a change to that script or the workflow, a source file moved into
`docs/`, and an error in the script. Its self-test, [scripts/ci-needs-build-selftest.sh](scripts/ci-needs-build-selftest.sh),
runs it against a throwaway repository.

Manual privacy checks (Airplane Mode, Instruments network trace, archive privacy report) are in [docs/qa/zero-network.md](docs/qa/zero-network.md).

## Contributing

- Read the ticket in [docs/backlog/](docs/backlog/README.md) first (one file per ticket). Its acceptance criteria are the definition of done.
  With Claude Code, run `/ticket SPS-<n>`.
- Project rules and conventions are in [CLAUDE.md](CLAUDE.md).
- Commit messages start with the ticket key, e.g. `SPS-2: bootstrap project structure`.
- Tests use Swift Testing (`import Testing`). User-facing strings go into `Localizable.xcstrings`.
