# SimilarPhotos

A native iOS app that finds near-duplicate photos in your library and helps you delete them.
Everything runs **on device**: the app makes no network calls, and photos that exist only in iCloud are skipped rather than downloaded.

> Status: early skeleton (SPS-2). Services are placeholders; see the [backlog](docs/jira-tickets.md).

## Requirements

- macOS with Xcode 16.4+ (Swift 6)
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
  -destination 'platform=iOS Simulator,name=iPhone 16'

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

CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs these on every pull request and on pushes to `main`:

| Check | Script |
|---|---|
| Domain imports only Foundation (Accelerate only in clustering) | [scripts/check-domain-imports.sh](scripts/check-domain-imports.sh) |
| Concrete Data types only in `AppContainer` | [scripts/check-concrete-construction.sh](scripts/check-concrete-construction.sh) |
| Remote packages only from [allowed-packages.txt](allowed-packages.txt): `Package.swift`, `project.yml` and every `Package.resolved` (transitive packages too) | [scripts/check-dependencies.sh](scripts/check-dependencies.sh) |
| Required Info.plist usage keys present; no network keys (ATS, local network, Bonjour, background fetch/push) or networking entitlements | [scripts/check-info-plist.sh](scripts/check-info-plist.sh) |
| Privacy manifest: no tracking, no collected data, and every required-reason API used in the sources is declared | [scripts/check-privacy-manifest.sh](scripts/check-privacy-manifest.sh) + [scripts/required-reason-apis.txt](scripts/required-reason-apis.txt) |
| No networking APIs or frameworks, no remote URL literals, `isNetworkAccessAllowed` only ever set to `false` | SwiftLint custom rules in [.swiftlint.yml](.swiftlint.yml) |

Each guard also has a **self-test**: CI runs it against a deliberately broken fixture in [scripts/fixtures/](scripts/fixtures/) and fails if the guard accepts it. When you change a rule, keep its fixture in sync.

After the guards, CI builds the app and runs `DomainTests`, `DataTests` and `PresentationTests`.

Manual privacy checks (Airplane Mode, Instruments network trace, archive privacy report) are in [docs/qa/zero-network.md](docs/qa/zero-network.md).

## Contributing

- Read the ticket in [docs/jira-tickets.md](docs/jira-tickets.md) first. Its acceptance criteria are the definition of done.
- Project rules and conventions are in [CLAUDE.md](CLAUDE.md).
- Commit messages start with the ticket key, e.g. `SPS-2: bootstrap project structure`.
- Tests use Swift Testing (`import Testing`). User-facing strings go into `Localizable.xcstrings`.
