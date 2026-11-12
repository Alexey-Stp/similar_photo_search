# SPS-32 — First TestFlight build and App Store submission

**Type:** Release task · **Epic:** SPS-27 · **Depends on:** SPS-29, SPS-31

## Description

No ticket takes the app to users yet. Prepare the project and the App Store Connect record, upload a Release build to
TestFlight, and submit the first version for App Review. Several pieces are missing today: the `AppIcon` set has an
empty 1024 px slot and no image, the bundle ID (`com.similarphotos.SimilarPhotos`) and version (`0.1.0`) in
`Config/Shared.xcconfig` are placeholders, and no signing team is set.

## Acceptance criteria

- `AppIcon` holds a 1024 × 1024 icon, and the archive builds without icon warnings.
- The bundle ID is registered in the team's developer account. `MARKETING_VERSION` is the release version, and
  `CURRENT_PROJECT_VERSION` goes up with every upload. Signing uses the team's account; no certificate, provisioning
  profile or App Store Connect key is committed.
- `Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false` (the app uses no encryption of its own), and
  `check-info-plist.sh` still passes.
- The App Store Connect record is complete: name, subtitle, description, keywords, category, support URL, privacy
  policy URL, the age rating questionnaire, and App Privacy set to **Data Not Collected**, matching
  `PrivacyInfo.xcprivacy`.
- The app links to the same privacy policy from an easily reachable place, and the link opens in Safari.
  `no_remote_url_literals` allows exactly that URL, and its fixture shows that any other web URL is still rejected.
- Screenshots in the iPhone sizes App Store Connect requires, made only from photos the team owns.
- A Release archive built with Xcode 26 (SPS-31) uploads, passes App Store Connect processing and installs from
  TestFlight. On that build a scan shows groups and a deletion works, both also in Airplane Mode.
- The first version is submitted for App Review, with review notes: no account needed, works offline, and how to see
  groups (take two or more photos of the same scene in a row, then scan).

## Technical notes

- App Review Guideline 5.1.1(i) wants the privacy policy linked in App Store Connect **and** inside the app, easily
  reachable (for example from onboarding or the home screen). The link opens in Safari, so the app itself still sends
  nothing. `no_remote_url_literals` rejects web URLs in the sources, so give it one narrow exception for exactly the
  policy URL entered in App Store Connect, with `// expect:` lines in `scripts/fixtures/NetworkViolations.swift`
  proving that this URL passes and any other URL still fires. The support URL lives only in App Store Connect.
- `TARGETED_DEVICE_FAMILY = 1` (iPhone only), but App Review also runs iPhone apps on iPad in compatibility mode.
  Open the TestFlight build on an iPad once before submitting.
- "Data Not Collected" stays true only while CLAUDE.md rule 1 holds: no analytics, crash reporter or other SDK that
  sends data.
- The string catalog has English only, so the store listing is English only.
- Agreements, tax and banking in App Store Connect are account tasks outside the repo.

## Risks

App Review can reject over metadata, the photo-library permission text or behaviour on iPad. A metadata-only rejection
is fixed in App Store Connect and answered in App Review, without a new build. A rejection of the binary (the
permission text lives in `Info.plist`; iPad behaviour) needs a new build and another review, so test the iPad path and
check the permission text before the first submission.

## Implementation notes
