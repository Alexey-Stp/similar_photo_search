import Domain
import DomainTestSupport
import Foundation
import Testing

struct AnalysisCoordinatorTests {
    typealias F = ScanFixture

    /// Three two-photo sessions on three days (s3 newest) and one single photo on another day.
    static let library: [PhotoAsset] = [
        F.photo("s1-a", session: 1, second: 0), F.photo("s1-b", session: 1, second: 5),
        F.photo("s2-a", session: 2, second: 0), F.photo("s2-b", session: 2, second: 5),
        F.photo("s3-a", session: 3, second: 0), F.photo("s3-b", session: 3, second: 5),
        F.photo("single", session: 5, second: 0)
    ]

    /// Each session's two photos show the same scene.
    static let prints: [FeaturePrint] = [
        F.print("s1-a", scene: 0), F.print("s1-b", scene: 0, jitter: 0.1),
        F.print("s2-a", scene: 1), F.print("s2-b", scene: 1, jitter: 0.1),
        F.print("s3-a", scene: 2), F.print("s3-b", scene: 2, jitter: 0.1),
        F.print("single", scene: 3)
    ]

    // MARK: - Publishing

    /// Sessions are published newest first, one `.added` per session, then `.finished`.
    /// Single photos never reach Vision.
    @Test func groupsArePublishedInSessionOrderAndSinglePhotosAreSkipped() async {
        let harness = ScanHarness(assets: Self.library, service: ScriptedFeaturePrintService(prints: Self.prints))
        let (updates, progress) = await harness.scan()

        // Cluster IDs are the newest member: the "-b" photo of each session.
        #expect(F.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
        #expect(updates.last == .finished)
        let onePerSession = updates.dropLast().allSatisfy { update in
            if case .added(let groups) = update { groups.count == 1 } else { false }
        }
        #expect(onePerSession)
        #expect(!harness.service.requestedIDs.contains("single"))
        #expect(Set(harness.service.requestedIDs) == Set(Self.library.map(\.id)).subtracting(["single"]))

        let last = progress.last
        #expect(last?.phase == .done)
        #expect(last?.processed == Self.library.count)
        #expect(last?.total == Self.library.count)
        #expect(last?.clusterCount == 3)
        #expect(last?.eta == 0)
        #expect(await harness.tracker.commitCallCount == 1)
    }

    /// Every group carries a Smart Selection suggestion built from the measured members.
    @Test func groupsCarryTheSmartSelectionSuggestion() async throws {
        let scorer = MockQualityScorer(measurements: [
            "s3-a": F.measurement(sharpness: 900), "s3-b": F.measurement(sharpness: 100)
        ])
        let assets = Array(Self.library[4...5])
        let harness = ScanHarness(
            assets: assets,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            scorer: scorer
        )
        let (updates, _) = await harness.scan()

        let selection = try #require(F.added(updates).first)
        #expect(selection.keeperID == "s3-a")
        #expect(selection.suggestedForDeletion == ["s3-b"])
        #expect(Set(scorer.calls) == ["s3-a", "s3-b"])
        // Prints and measurements are written together, in one upsert per session.
        let upserts = await harness.cache.upsertCalls
        #expect(upserts.count == 1)
        #expect(upserts.first?.allSatisfy { $0.quality?.version == 1 && $0.featurePrint != nil } == true)
    }

    /// Skipped and failed photos are counted and left out; skips are not cached.
    @Test func skipsAndFailuresAreCountedNotCompared() async {
        let assets = [
            F.photo("a", session: 1, second: 0), F.photo("b", session: 1, second: 5),
            F.photo("cloud", session: 1, second: 10), F.photo("broken", session: 1, second: 15)
        ]
        let service = ScriptedFeaturePrintService(outcomes: [
            "a": .computed(F.print("a", scene: 0)),
            "b": .computed(F.print("b", scene: 0, jitter: 0.1)),
            "broken": .failed(.vision)
        ])
        let harness = ScanHarness(assets: assets, service: service)
        let (updates, progress) = await harness.scan()

        #expect(F.added(updates).map(\.cluster.assetIDs) == [["b", "a"]])
        #expect(progress.last?.skipped == [.iCloudOnly: 1])
        #expect(progress.last?.failed == 1)
        #expect(progress.last?.processed == 4)
        #expect(await harness.cache.cachedAssetIDs() == ["a", "b", "broken"])
    }

    /// Photos without a date are counted as skipped (no date) and never analysed.
    @Test func undatedPhotosAreCountedAsSkipped() async {
        let undated = PhotoAsset(
            id: "undated", creationDate: nil, pixelWidth: 1, pixelHeight: 1, isFavorite: false, mediaSubtypes: []
        )
        let harness = ScanHarness(
            assets: Self.library + [undated],
            service: ScriptedFeaturePrintService(prints: Self.prints)
        )
        let (_, progress) = await harness.scan()
        #expect(progress.last?.skipped[.noDate] == 1)
        #expect(progress.last?.processed == Self.library.count + 1)
        #expect(!harness.service.requestedIDs.contains("undated"))
    }

    /// A revision without a calibrated threshold is an error, not "no duplicates".
    @Test func missingThresholdFailsTheScan() async {
        let harness = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            clusteringConfig: ClusteringConfig(thresholds: [:])
        )
        let (updates, progress) = await harness.scan()
        #expect(progress.last?.phase == .failed(.missingThreshold(revision: F.revision)))
        #expect(updates == [.finished])
        #expect(await harness.tracker.commitCallCount == 0)
        // The prints computed before the failure are kept.
        #expect(await harness.cache.cachedAssetIDs() == ["s3-a", "s3-b"])
    }

    // MARK: - Resume and reuse

    /// Photos with a valid cached print are not analysed again (resume after a kill).
    @Test func cachedPhotosAreNotAnalysedAgain() async {
        let cache = MockFeaturePrintCache(featurePrints: Array(Self.prints[0...3]))
        let harness = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            cache: cache
        )
        let (updates, _) = await harness.scan()
        #expect(Set(harness.service.requestedIDs) == ["s3-a", "s3-b"])
        #expect(F.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// A large session saves its new prints every `persistBatchSize` photos, so a killed app loses at most one batch.
    @Test func largeSessionsSavePrintsInBatches() async {
        let photos = (0..<7).map { F.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<7).map { F.print("p\($0)", scene: $0) }
        let harness = ScanHarness(
            assets: photos,
            service: ScriptedFeaturePrintService(prints: prints),
            settings: AnalysisCoordinator.Settings(progressInterval: 0, persistBatchSize: 3)
        )
        _ = await harness.scan()
        // Batches of 3, 3 and 1: the first two are saved at once, the last with the quality step.
        #expect(await harness.cache.upsertCalls.map(\.count) == [3, 3, 1])
        #expect(await harness.cache.cachedAssetIDs().count == 7)
    }

    /// A second scan of an unchanged library reuses the stored clusters: no Vision, no clustering, same groups.
    @Test func unchangedSessionsReuseStoredClusters() async {
        let first = ScanHarness(assets: Self.library, service: ScriptedFeaturePrintService(prints: Self.prints))
        let (firstUpdates, _) = await first.scan()
        #expect(await first.results.storedResults().count == 3)

        let second = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            cache: first.cache,
            results: first.results
        )
        let (secondUpdates, _) = await second.scan()
        #expect(second.service.requestedIDs.isEmpty)
        #expect(second.clustering.callCount == 0)
        #expect(F.addedIDs(secondUpdates) == F.addedIDs(firstUpdates))
        #expect(F.removedIDs(secondUpdates).isEmpty)
    }

    /// A deleted photo breaks its group: the group is published as removed and its session result is dropped.
    @Test func sessionsThatLostPhotosArePublishedAsRemoved() async {
        let first = ScanHarness(assets: Self.library, service: ScriptedFeaturePrintService(prints: Self.prints))
        _ = await first.scan()

        let tracker = MockLibraryChangeTracker(report: .changes(LibraryDelta(deleted: ["s2-a"])))
        let second = ScanHarness(
            assets: Self.library.filter { $0.id != "s2-a" },
            service: ScriptedFeaturePrintService(prints: Self.prints),
            cache: first.cache,
            results: first.results,
            tracker: tracker
        )
        let (updates, _) = await second.scan()
        #expect(F.addedIDs(updates) == ["s3-b", "s1-b"])
        #expect(F.removedIDs(updates) == ["s2-b"])
        #expect(await second.results.storedResults().map(\.sessionID).allSatisfy { !$0.hasPrefix("s2-b@") })
        #expect(await second.tracker.commitCallCount == 1)
    }

    /// A new similar photo joins a session: the session is re-clustered, its group replaced under the same ID.
    @Test func aGrownSessionIsReclusteredWithOnlyTheNewPhotoAnalysed() async {
        let first = ScanHarness(assets: Self.library, service: ScriptedFeaturePrintService(prints: Self.prints))
        _ = await first.scan()

        let newPhoto = F.photo("s1-c", session: 1, second: 2)
        let tracker = MockLibraryChangeTracker(report: .changes(LibraryDelta(inserted: ["s1-c"])))
        let second = ScanHarness(
            assets: Self.library + [newPhoto],
            service: ScriptedFeaturePrintService(prints: Self.prints + [F.print("s1-c", scene: 0, jitter: 0.05)]),
            cache: first.cache,
            results: first.results,
            tracker: tracker
        )
        let (updates, _) = await second.scan()
        #expect(second.service.requestedIDs == ["s1-c"])
        #expect(second.clustering.callCount == 1)
        #expect(F.added(updates).last?.cluster.assetIDs == ["s1-b", "s1-c", "s1-a"])
        #expect(F.removedIDs(updates).isEmpty, "The same ID is replaced, not removed")
    }

    /// Changing the session config recomputes clusters (stored results are stale) but keeps cached prints.
    @Test func aNewSessionConfigReclustersWithoutNewVision() async {
        let first = ScanHarness(assets: Self.library, service: ScriptedFeaturePrintService(prints: Self.prints))
        _ = await first.scan()

        let second = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            cache: first.cache,
            results: first.results
        )
        let (updates, _) = await second.scan(sessionConfig: SessionConfig(sessionGap: SessionGapPreset.strict.interval))
        #expect(second.service.requestedIDs.isEmpty)
        #expect(second.clustering.callCount == 3)
        #expect(F.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
        let keys = Set(await second.results.storedResults().map(\.resultsKey))
        #expect(keys.count == 1, "Results of the old config are dropped")
    }

    // MARK: - Cancellation

    /// Cancel stops the scan within 500 ms; prints finished before it are saved; nothing is committed.
    @Test func cancelStopsWithin500msAndKeepsFinishedWork() async throws {
        let service = ScriptedFeaturePrintService(prints: Self.prints, blocked: ["s3-b"])
        let harness = ScanHarness(
            assets: Self.library,
            service: service,
            settings: AnalysisCoordinator.Settings(fullConcurrency: 2, progressInterval: 0)
        )
        let streams = await harness.start()
        let collected = Task { await F.collect(streams) }
        #expect(await eventually { service.requestedIDs.contains("s3-b") && service.requestedIDs.contains("s3-a") })
        try await Task.sleep(for: .milliseconds(20))

        let clock = ContinuousClock()
        let started = clock.now
        await harness.coordinator.cancel()
        let (updates, progress) = await collected.value
        let elapsed = clock.now - started

        #expect(elapsed < .milliseconds(500))
        #expect(progress.last?.phase == .cancelled)
        #expect(updates == [.finished])
        #expect(await harness.cache.cachedAssetIDs() == ["s3-a"], "The finished print is saved")
        #expect(await harness.tracker.commitCallCount == 0)
        #expect(!service.requestedIDs.contains("s2-a"))
    }

    /// After a cancelled scan, a new scan only analyses what was left.
    @Test func aScanAfterACancelOnlyAnalysesTheRest() async throws {
        let blocking = ScriptedFeaturePrintService(prints: Self.prints, blocked: ["s2-a", "s2-b"])
        let first = ScanHarness(assets: Self.library, service: blocking)
        let streams = await first.start()
        let collected = Task { await F.collect(streams) }
        #expect(await eventually { blocking.requestedIDs.contains("s2-a") })
        await first.coordinator.cancel()
        let (firstUpdates, _) = await collected.value
        #expect(F.addedIDs(firstUpdates) == ["s3-b"])

        let second = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            cache: first.cache,
            results: first.results
        )
        let (updates, _) = await second.scan()
        #expect(Set(second.service.requestedIDs) == ["s2-a", "s2-b", "s1-a", "s1-b"])
        #expect(F.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// Starting a new scan cancels the running one; the new scan runs to the end.
    @Test func startingAgainCancelsTheRunningScan() async {
        let service = ScriptedFeaturePrintService(prints: Self.prints, blocked: ["s3-a"])
        let harness = ScanHarness(assets: Self.library, service: service)
        let firstStreams = await harness.start()
        let first = Task { await F.collect(firstStreams) }
        #expect(await eventually { service.requestedIDs.contains("s3-a") })

        let secondStreams = await harness.start()
        service.unblock(["s3-a"])
        let (_, firstProgress) = await first.value
        let (secondUpdates, secondProgress) = await F.collect(secondStreams)
        #expect(firstProgress.last?.phase == .cancelled)
        #expect(secondProgress.last?.phase == .done)
        #expect(F.addedIDs(secondUpdates) == ["s3-b", "s2-b", "s1-b"])
    }

    // MARK: - Deleted during the scan

    /// Photos deleted while the scan runs are never loaded, analysed or published.
    @Test func photosDeletedDuringTheScanAreNeverAnalysed() async {
        let service = ScriptedFeaturePrintService(prints: Self.prints, blocked: ["s3-a"])
        let harness = ScanHarness(assets: Self.library, service: service)
        let streams = await harness.start()
        let collected = Task { await F.collect(streams) }
        #expect(await eventually { service.requestedIDs.contains("s3-a") })

        await harness.coordinator.excludeDeleted(["s2-a", "s1-b"])
        service.unblock(["s3-a"])
        let (updates, progress) = await collected.value

        #expect(!service.requestedIDs.contains("s2-a"))
        #expect(!service.requestedIDs.contains("s1-b"))
        #expect(F.addedIDs(updates) == ["s3-b"])
        #expect(progress.last?.phase == .done)
    }

    // MARK: - Throttling

    /// Nominal conditions use the full width; `.serious` drops it to one photo at a time.
    @Test func seriousThermalStateDropsConcurrencyToOne() async {
        let manyPhotos = (0..<12).map { F.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<12).map { F.print("p\($0)", scene: 0) }

        let nominal = ScanHarness(
            assets: manyPhotos,
            service: ScriptedFeaturePrintService(prints: prints, delay: .milliseconds(15))
        )
        _ = await nominal.scan()
        #expect(nominal.service.maxConcurrency > 1)
        #expect(nominal.service.maxConcurrency <= 4)

        let hot = ScanHarness(
            assets: manyPhotos,
            service: ScriptedFeaturePrintService(prints: prints, delay: .milliseconds(5)),
            thermal: MockThermalMonitor(conditions: ScanConditions(thermalLevel: .serious))
        )
        let (_, progress) = await hot.scan()
        #expect(hot.service.maxConcurrency == 1)
        #expect(progress.last?.conditions.thermalLevel == .serious)
    }

    /// Low Power Mode drops the width to two and is reported, so the UI can show a notice.
    @Test func lowPowerModeDropsConcurrency() async {
        let manyPhotos = (0..<12).map { F.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<12).map { F.print("p\($0)", scene: 0) }
        let harness = ScanHarness(
            assets: manyPhotos,
            service: ScriptedFeaturePrintService(prints: prints, delay: .milliseconds(10)),
            thermal: MockThermalMonitor(conditions: ScanConditions(isLowPowerModeEnabled: true))
        )
        let (_, progress) = await harness.scan()
        #expect(harness.service.maxConcurrency <= ScanConditions.lowPowerConcurrency)
        #expect(progress.allSatisfy { $0.conditions.isLowPowerModeEnabled })
    }

    /// At `.critical` the scan pauses (phase `.throttled`) and goes on when the device cools down.
    @Test func criticalThermalStatePausesUntilCooler() async {
        let thermal = MockThermalMonitor(conditions: ScanConditions(thermalLevel: .critical))
        let harness = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            thermal: thermal
        )
        let streams = await harness.start()
        let collected = Task { await F.collect(streams) }
        #expect(await eventually { thermal.subscriberCount > 0 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(harness.service.requestedIDs.isEmpty, "Nothing is analysed while critical")

        thermal.set(ScanConditions(thermalLevel: .fair))
        let (updates, progress) = await collected.value
        #expect(progress.contains { $0.phase == .throttled })
        #expect(progress.last?.phase == .done)
        #expect(F.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// Cancel works while the scan is paused.
    @Test func cancelEndsAPausedScan() async {
        let thermal = MockThermalMonitor(conditions: ScanConditions(thermalLevel: .critical))
        let harness = ScanHarness(
            assets: Self.library,
            service: ScriptedFeaturePrintService(prints: Self.prints),
            thermal: thermal
        )
        let streams = await harness.start()
        let collected = Task { await F.collect(streams) }
        #expect(await eventually { thermal.subscriberCount > 0 })
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.cancel()
        let (_, progress) = await collected.value
        #expect(progress.last?.phase == .cancelled)
    }

    // MARK: - Progress

    /// With the default interval, a burst of work publishes far fewer snapshots than photos.
    @Test func progressIsThrottled() async {
        let manyPhotos = (0..<200).map { F.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<200).map { F.print("p\($0)", scene: $0 % 4) }
        let harness = ScanHarness(
            assets: manyPhotos,
            service: ScriptedFeaturePrintService(prints: prints),
            settings: AnalysisCoordinator.Settings(progressInterval: 10)
        )
        let (_, progress) = await harness.scan()
        // Only forced snapshots (phase changes, conditions, the end) get through a 10 s interval.
        #expect(progress.count < 10)
        #expect(progress.last?.processed == 200)
    }
}
