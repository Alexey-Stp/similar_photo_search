# SPS-29 — Device QA and performance pass

**Type:** QA task · **Epic:** SPS-27 · **Depends on:** SPS-28

## Description

Most epic "Done when" targets can only be checked on a physical device, and each ticket from SPS-9 onwards left a
"device QA still open" list in its implementation notes. Run them all in one pass on a calibrated build (SPS-28), and
record the results. Fix small problems here; open new tickets for anything bigger.

## Acceptance criteria

- **Performance tests.** Run every device-only test with `RUN_DEVICE_PERFORMANCE_TESTS=1` on the stated hardware, and
  record the results in the implementation notes. Each one passes, or has its own follow-up ticket:
  - `PhotoLibraryPerformanceTests` (SPS-7)
  - `ImageLoadingPerformanceTests` (SPS-9)
  - `VisionFeaturePrintDeviceTests` (SPS-12)
  - `AnalysisCachePerformanceTests` (SPS-13)
  - `ClusteringPerformanceTests` (SPS-16)
  - `QualityScoringDeviceTests` (SPS-17)
- **Epic targets measured on a device:**
  - enumerating 50k photos takes < 2 s
  - image-loading peak memory is < 250 MB on an iPhone 12
  - analysis runs at ≥ 25 images/s on an iPhone 13
  - the first groups appear within 5 s on a 10k library
  - a second launch reaches clusters in < 3 s
  - no hitches in Instruments while scrolling 1,000 groups
- **Manual QA lists.** Work through every open device or manual QA list in the implementation notes of SPS-9, SPS-10,
  SPS-12, SPS-13, SPS-14, SPS-17, SPS-18, SPS-20, SPS-21, SPS-22, SPS-24 and SPS-25. Tick off each item in its ticket
  file, or link the follow-up ticket.
- **Zero network.** Run [docs/qa/zero-network.md](../qa/zero-network.md) in full over a complete scan and a deletion on a
  Release build: Airplane Mode, the Instruments network trace and the archive privacy report.
- **Accessibility.** VoiceOver, AX5 Dynamic Type and Dark Mode on every screen.
- **Limited access.** Scanning, change tracking and deletion all work under Limited access.

## Technical notes

Use Instruments (Allocations, Time Profiler, Hitches, Network) on a Release build. Write down the device model and iOS
version with every number.

## Implementation notes
