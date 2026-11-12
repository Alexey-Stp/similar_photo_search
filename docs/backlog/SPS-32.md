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
- Screenshots in the iPhone sizes App Store Connect requires, made only from photos the team owns.
- A Release archive built with Xcode 26 (SPS-31) uploads, passes App Store Connect processing and installs from
  TestFlight. On that build a scan shows groups and a deletion works, both also in Airplane Mode.
- The first version is submitted for App Review, with review notes: no account needed, works offline, and how to see
  groups (take two or more photos of the same scene in a row, then scan).

## Technical notes

- The support and privacy policy URLs live only in App Store Connect. The app must not contain them: the
  `no_remote_url_literals` SwiftLint rule rejects web URLs in the sources.
- `TARGETED_DEVICE_FAMILY = 1` (iPhone only), but App Review also runs iPhone apps on iPad in compatibility mode.
  Open the TestFlight build on an iPad once before submitting.
- "Data Not Collected" stays true only while CLAUDE.md rule 1 holds: no analytics, crash reporter or other SDK that
  sends data.
- The string catalog has English only, so the store listing is English only.
- Agreements, tax and banking in App Store Connect are account tasks outside the repo.

## Risks

App Review can reject over metadata, the photo-library permission text or behaviour on iPad. Each rejection costs a
new build and another review, so test the iPad path and write clear review notes before the first submission.

## Implementation notes
