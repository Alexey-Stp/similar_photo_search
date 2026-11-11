# Zero-network and privacy QA (SPS-5)

The app promises that it does not transmit anything: no networking code, no analytics, no third-party SDKs, and iCloud-only originals are skipped rather than downloaded.
CI enforces the code side (see [README → Guard rails](../../README.md#guard-rails)). This checklist covers what only a person with a device can check.

Run it before every release, and again whenever scanning (SPS-14), deletion (SPS-24/SPS-25) or a new framework is added.

> **Current scope.** Scanning (SPS-14) and the deletion service (SPS-24) exist; the deletion UI arrives with SPS-25. Until then, the deletion steps of checks 1 and 2 need a Debug build that calls `AssetDeletionService.delete(assetIDs:)` on a few photos (for example from a temporary button). Once SPS-25 lands, run the full flow including deletion from the UI.

## 1. Airplane Mode parity

Device: a physical iPhone with iCloud Photos on and "Optimize iPhone Storage" selected, so the library has some iCloud-only originals.

**Before the first run**

- Put a few photos you know are iCloud-only (opening them in Photos while offline fails to load the full image) into an album named `QA iCloud-only`. These are the reference for local-original availability.
- Both runs must start from the **same library state**. Either restore everything the first run deleted (Photos → Recently Deleted → Recover) before the second run, or use a dedicated test device and reset it to the same fixture library before each run.

**Offline run**

1. While the device is **online**, delete the app and install a Release build (TestFlight or Xcode with the Release configuration). **Do not open it yet.**
2. Turn on Airplane Mode **and** turn Wi-Fi and Bluetooth off. Only then launch the app.
3. Complete onboarding and the permission prompt, run a full scan, review the groups and delete a few photos.
4. Note the results: groups found, photos scanned, skipped counts (iCloud-only, no date), deleted count.
5. Check that the photos in `QA iCloud-only` are still iCloud-only.

**Online run**

6. Turn networking back on and restore the library state (see above).
7. Pause iCloud Photos syncing for the duration of the run (Photos → your account → Pause, or Low Power Mode), so availability doesn't change while the app scans.
8. Delete the app, reinstall the same build, launch it and repeat steps 3–5.

**Pass**

- Both runs behave the same: nothing hangs or shows a network error.
- The no-date skip count matches. It doesn't depend on where originals are stored.
- Groups found, photos scanned and the iCloud-only skip count are compared **only if** local-original availability was the same in both runs, meaning the `QA iCloud-only` photos were iCloud-only before and after each run. All three depend on which originals are on the device: an iCloud-only photo is skipped, so it is neither scanned nor grouped. If availability changed between runs (iOS downloaded or offloaded originals), record these comparisons as **inconclusive** and repeat both runs with the same availability, rather than marking them as a pass or a fail.
- After either run, the `QA iCloud-only` photos are still iCloud-only. If one became local, the app (or a request on its behalf) downloaded it, and the check **fails**.

## 2. No outbound connections

1. Connect the device to a Mac. In Xcode, choose **Product → Profile** (Release) and pick the **Network** template (Network Connections instrument).
2. Record from launch through onboarding, a full scan, opening a comparison view and one deletion.
3. Filter the trace by the `SimilarPhotos` process.
4. Repeat the recording with a **debuggable (Debug) build** and add the **HTTP Traffic** instrument. It also shows background `URLSession` transfers that a system daemon runs on the app's behalf. HTTP Traffic only works for debuggable builds.

**Pass:** zero connections, sockets or DNS lookups by `SimilarPhotos`, and no HTTP transactions attributed to the app in HTTP Traffic.

What counts:

- **Independent iCloud Photos sync** (`cloudd`, `photoanalysisd`, `nsurlsessiond` uploading or downloading on its own schedule) is outside the app's control and does **not** count.
- **Transfers requested by the app count even when a system daemon performs them.** Examples: a background `URLSession` run by `nsurlsessiond`, or a PhotoKit request with network access that makes `cloudd` download an original. Evidence: HTTP Traffic attributes the transaction to the app, or an iCloud-only reference photo becomes local after the app touched it (check 1).

Optional cross-check with a proxy (Charles, Proxyman): a device-wide HTTP proxy usually can't tell which app made a request. Requests without the app's bundle ID or user agent are **not** proof that the app sent nothing. Treat the proxy as a hint only. A pass needs **process-attributed** evidence: the Network Connections and HTTP Traffic instruments filtered by the `SimilarPhotos` process.

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
