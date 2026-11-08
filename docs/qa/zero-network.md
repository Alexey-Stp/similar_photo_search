# Zero-network and privacy QA (SPS-5)

The app promises that it does not transmit anything: no networking code, no analytics, no third-party SDKs, and iCloud-only originals are skipped rather than downloaded.
CI enforces the code side (see [README → Guard rails](../../README.md#guard-rails)). This checklist covers what only a person with a device can check.

Run it before every release, and again whenever scanning (SPC-14), deletion (SPC-24/SPC-25) or a new framework is added.

> **Current scope.** Scanning, analysis and deletion are still placeholders. Until SPC-14 and SPC-24 land, run checks 1 and 2 on the flows that exist (onboarding, permission prompt, Limited/Denied screens, Home). Re-run them over a full scan and a deletion as part of the definition of done for SPC-14, SPC-24 and SPC-25.

## 1. Airplane Mode parity

Device: a physical iPhone with a library that has some iCloud-only originals ("Optimize iPhone Storage" on).

1. Delete the app. Turn on Airplane Mode **and** turn Wi-Fi and Bluetooth off.
2. Install a Release build (TestFlight or Xcode with the Release configuration) and complete onboarding and the permission prompt.
3. Run a full scan, review the groups and delete a few photos.
4. Note the results: groups found, photos scanned, skipped counts (iCloud-only, no date), deleted count.
5. Turn networking back on, delete the app and repeat steps 2–4 on the same library.

**Pass:** both runs behave the same. Nothing hangs or shows a network error, and the counts match (iCloud-only photos are skipped in both runs).

## 2. No outbound connections

1. Connect the device to a Mac. In Xcode, choose **Product → Profile** (Release) and pick the **Network** template (Network Connections instrument).
2. Record from launch through onboarding, a full scan, opening a comparison view and one deletion.
3. Filter the trace by the `SimilarPhotos` process.

**Pass:** zero connections, sockets or DNS lookups by `SimilarPhotos`.
Traffic from system daemons (`cloudd`, `photoanalysisd`, `nsurlsessiond` for iCloud Photos sync) is outside the app's control and does not count.

Optional cross-check: route the device through a proxy such as Charles or Proxyman and confirm that no request comes from the app's bundle ID.

## 3. Privacy report

1. Archive a Release build (**Product → Archive**).
2. In the Organizer, right-click the archive and choose **Generate Privacy Report**.

**Pass:** no warnings or missing-reason entries. The report lists only `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`), with no tracking domains and no collected data types.

## 4. App Store privacy label

In App Store Connect → App Privacy, the answer to "Do you or your third-party partners collect data from this app?" is **No**, so the label reads **"Data Not Collected"**.
This is honest only while checks 1–3 pass and `NSPrivacyCollectedDataTypes` is empty (CI checks that).

## Results log

| Date | Build | Device | iOS | Checks run | Result | Tester |
|---|---|---|---|---|---|---|
| | | | | | | |
