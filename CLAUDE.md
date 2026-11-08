# CLAUDE.md — SimilarPhotos (iOS)

Native iOS app that finds near-duplicate photos in the user's library and helps delete them.
Backlog with all tickets (SPC-1 … SPC-25), acceptance criteria and AI prompts: [docs/jira-tickets.md](docs/jira-tickets.md).
When working on a ticket, read its section there first and treat its Acceptance Criteria as the definition of done.

## Non-negotiable rules

1. **Zero network.** Never add `URLSession`, `URLRequest`, `NWConnection`, `WKWebView`, analytics, crash reporters or any third-party SDK that can talk to the network.
   Every `PHImageRequestOptions` must set `isNetworkAccessAllowed = false`. iCloud-only originals are **skipped**, never downloaded.
2. **Never delete without the user's explicit action.** Favorites are never auto-selected. Each cluster keeps at least one photo unless the user confirms otherwise.
3. **Memory discipline.** Never keep collections of full-size `UIImage`/`CGImage`. Analysis images are ~512 px. Wrap per-image work in `autoreleasepool`. Process in bounded batches.
4. **No `PHAsset` across actor boundaries.** Pass `localIdentifier` strings or `Sendable` domain structs.
5. Do not add new SPM dependencies without asking. Allowed list lives in `allowed-packages.txt`.

## Stack

- Swift 6 (strict concurrency `complete`), SwiftUI, iOS 17.0 minimum.
- PhotoKit (`PHAsset`, `PHImageManager`, `PHCachingImageManager`, `PHPhotoLibrary`, persistent change tokens).
- Vision: `VNGenerateImageFeaturePrintRequest` (Revision2), `VNDetectFaceCaptureQualityRequest`, `VNCalculateImageAestheticsScoresRequest` (iOS 18+, behind `#available`).
- Accelerate (`vDSP`, `vImage`) for distances and sharpness.
- SwiftData for the feature-print cache, written only through a `@ModelActor`.

## Architecture (Clean Architecture + MVVM)

```
SimilarPhotos/            app target — composition root (AppContainer), Info.plist, PrivacyInfo.xcprivacy
Packages/Domain/          entities, use cases, repository/service protocols — Foundation only
Packages/Data/            PhotoKit, Vision, SwiftData implementations of Domain protocols
Packages/Presentation/    SwiftUI views + @Observable @MainActor view models
docs/                     backlog and design notes
```

- `Domain` must not import `Photos`, `Vision`, `SwiftData`, `SwiftUI` or `UIKit` (CI enforces this). `Accelerate` is allowed only in the clustering engine.
- Concrete types are created only in `AppContainer`; everything else receives protocols through initializers.
- Stateful services are `actor`s. View models are `@Observable @MainActor final class`.
- Long work uses structured concurrency (`TaskGroup` with a fixed width), checks cancellation, and reports progress via `AsyncStream` (throttled to ≤10 updates/s).
- Return value types from `@ModelActor`, never `@Model` instances.

## Key domain facts

- Feature-print vectors are stored as raw `[Float]` packed into `Data`, together with their Vision **revision**. Never compare vectors of different revisions.
- Cache entry is valid only if `assetID`, `revision` and `PHAsset.modificationDate` all match.
- **Similar photos are taken close together in time.** Photos are split into shooting sessions: a run where every gap between neighbouring shots is ≤ `sessionGap` (default 15 min). Only photos from the same session are compared; photos from different days never are. Single-photo sessions skip Vision entirely (SPC-26).
- Clustering works on one session at a time: pairs within `maxPairInterval` → distance threshold → Union-Find → chaining guard for big components. Threshold and session gap are tuned on the labelled fixture set, never guessed; the threshold is keyed by revision.
- **Results are shown while scanning.** The coordinator processes sessions newest first and publishes each session's groups immediately via `AsyncStream<ClusterUpdate>`. The UI only appends groups and never moves rows under the user. Photos deleted during a scan are excluded from the rest of it.
- Accepted trade-off: copies of the same picture saved on different days are not found.
- Deletion goes through one `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.deleteAssets`. `PHPhotosError.userCancelled` is a normal outcome, not an error.

## Commands

```bash
# generate the Xcode project (SimilarPhotos.xcodeproj is not committed)
xcodegen generate

# build + test (adjust simulator name to one installed)
xcodebuild test -scheme SimilarPhotos -destination 'platform=iOS Simulator,name=iPhone 16'

# package-level tests
swift test --package-path Packages/Domain

# lint (includes zero-network custom rules)
swiftlint --strict
```

Vision feature prints and performance numbers must be checked on a **physical device**; the Simulator gives different results.

## Code style

- Swift API Design Guidelines; doc comments on public API.
- Tests with Swift Testing (`import Testing`); every service has a protocol and a mock.
- User-facing strings go into `Localizable.xcstrings`. Every interactive view has VoiceOver labels and supports Dynamic Type and Dark Mode.
- Logging via `os.Logger`; asset identifiers and any user data use `privacy: .private`.
- Commit messages reference the ticket key, e.g. `SPC-12: add feature print service`.
