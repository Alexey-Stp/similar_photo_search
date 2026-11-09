---
name: ticket
description: Use when asked to implement, plan or continue a backlog ticket of this repo (for example "/ticket SPS-9", "do SPS-26", "next ticket"), from reading the spec to a branch with tests and updated backlog notes.
---

# Implementing a backlog ticket

The argument is a ticket key such as `SPS-9`. With no key, pick the first **To do** ticket in
`docs/backlog/README.md` whose dependencies are all **Done**, and say which one you picked.

If the user only asks for a plan, do steps 1–2 and the mapping part of step 3, return the plan and stop: no branch, no code,
no backlog edits. Go on with the rest only when the user asks for the implementation.

## 1. Read (only these)

1. `docs/backlog/README.md`: product principles, the ticket's row (status, dependencies).
2. `docs/backlog/<KEY>.md`: the spec. Acceptance criteria are the definition of done.
3. The **Implementation notes** of the tickets it depends on (same folder). They record decisions that override the original
   spec text, for example a type that was renamed or a contract that was tightened.
4. The existing code the ticket touches. "Implementation hints" were written before the code: when a hint names a type that
   already exists under another name or shape (the SPS-2 placeholders in `Packages/Domain/Sources/Domain/Protocols`), extend
   the existing one instead of adding a parallel type.

Do not read other ticket files unless the spec points to them, with one exception: before step 6 adds a line to a later
ticket, read that ticket (the index shows which tickets depend on this one).

## 2. Check before coding

- If a dependency is not **Done**, stop and tell the user which one is missing.
- If an acceptance criterion conflicts with CLAUDE.md, the code, or a dependency's implementation notes, raise it before coding.
  The rules in CLAUDE.md always win (zero network, memory, no `PHAsset` across actors, no new packages).
- If the ticket needs a required-reason API, an Info.plist key or a new SPM package, check `scripts/` and the allow-lists first.

## 3. Branch and plan

- First check for unfinished work on this ticket (`git branch -a --list '*SPS-<n>*'`, an open PR). If there is one, continue
  on that branch; if it is unclear which branch holds the work, ask the user.
- Otherwise branch from an up-to-date `main`: `SPS-<n>-<short-slug>` (for example `SPS-26-session-segmenter`).
- Map each acceptance criterion to the test or check that proves it. Criteria that need a device (performance, Vision,
  memory, Airplane Mode) get a device-only test or a manual QA step, never a silent skip.

## 4. Implement

- Tests first where the logic is pure (Domain, view models). Swift Testing; mocks in `DomainTestSupport`, preview fakes in `Presentation/Previews`.
- New concrete types are constructed only in `SimilarPhotos/AppContainer.swift`.
- User-facing strings go into `Localizable.xcstrings`, with VoiceOver labels, Dynamic Type and Dark Mode.

## 5. Verify

Run what the environment allows and report exactly what ran and what did not:

```bash
bash scripts/check-domain-imports.sh && bash scripts/check-concrete-construction.sh && bash scripts/check-privacy-manifest.sh
swift test --package-path Packages/Domain -Xswiftc -warnings-as-errors
swift test --package-path Packages/Data -Xswiftc -warnings-as-errors
xcodegen generate && xcodebuild test -scheme SimilarPhotos -destination 'platform=iOS Simulator,name=iPhone 16'
swiftlint --strict
```

On a machine without Xcode (Windows, Linux), still run what the installed Swift toolchain supports: `Packages/Domain` is
Foundation-only, so run its tests when `swift` is available. `Packages/Data`, the app build and SwiftLint need Apple
frameworks or macOS; report exactly those (and anything else that could not run) as unverified.

## 6. Update the backlog

- Append `## Implementation notes` to `docs/backlog/<KEY>.md`: decisions, deviations from the spec, renamed types, anything
  a later ticket must know, and device-only checks still open. Keep it to facts a reader can't get from the diff.
- Set the ticket's status in `docs/backlog/README.md` to **Review** while the PR is open. After the PR merges, set it to
  **Done** on `main` (the branch only ever carries **Review**), or ask the user to.
- If the work changes what a later ticket should do, add one line to that ticket's file instead of leaving it in your head.

## 7. Commit and PR (only when the user asks)

Commit messages start with the key: `SPS-26: add session segmenter`. For the PR, use the `pr-description` skill.
