import Domain
import DomainTestSupport
import Foundation
import Testing

/// Publishing order, skips, resume from the cache and reuse of stored results.
struct AnalysisCoordinatorTests {
    typealias Fixture = ScanFixture

    // MARK: - Publishing

    /// Sessions are published newest first, one `.added` per session, then `.finished`.
    /// Single photos never reach Vision.
    @Test func groupsArePublishedInSessionOrderAndSinglePhotosAreSkipped() async {
        let harness = ScanHarness(assets: Fixture.library, service: ScriptedFeaturePrintService(prints: Fixture.prints))
        let (updates, progress) = await harness.scan()

        // Cluster IDs are the newest member: the "-b" photo of each session.
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
        #expect(updates.last == .finished)
        let onePerSession = updates.dropLast().allSatisfy { update in
            if case .added(let groups) = update { groups.count == 1 } else { false }
        }
        #expect(onePerSession)
        #expect(!harness.service.requestedIDs.contains("single"))
        #expect(Set(harness.service.requestedIDs) == Set(Fixture.library.map(\.id)).subtracting(["single"]))

        let last = progress.last
        #expect(last?.phase == .done)
        #expect(last?.processed == Fixture.library.count)
        #expect(last?.total == Fixture.library.count)
        #expect(last?.clusterCount == 3)
        #expect(last?.eta == 0)
        #expect(await harness.tracker.commitCallCount == 1)
    }

    /// Every group carries a Smart Selection suggestion built from the measured members.
    @Test func groupsCarryTheSmartSelectionSuggestion() async throws {
        let scorer = MockQualityScorer(measurements: [
            "s3-a": Fixture.measurement(sharpness: 900), "s3-b": Fixture.measurement(sharpness: 100)
        ])
        let assets = Array(Fixture.library[4...5])
        let harness = ScanHarness(
            assets: assets,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            scorer: scorer
        )
        let (updates, _) = await harness.scan()

        let selection = try #require(Fixture.added(updates).first)
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
            Fixture.photo("a", session: 1, second: 0), Fixture.photo("b", session: 1, second: 5),
            Fixture.photo("cloud", session: 1, second: 10), Fixture.photo("broken", session: 1, second: 15)
        ]
        let service = ScriptedFeaturePrintService(outcomes: [
            "a": .computed(Fixture.print("a", scene: 0)),
            "b": .computed(Fixture.print("b", scene: 0, jitter: 0.1)),
            "broken": .failed(.vision)
        ])
        let harness = ScanHarness(assets: assets, service: service)
        let (updates, progress) = await harness.scan()

        #expect(Fixture.added(updates).map(\.cluster.assetIDs) == [["b", "a"]])
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
            assets: Fixture.library + [undated],
            service: ScriptedFeaturePrintService(prints: Fixture.prints)
        )
        let (_, progress) = await harness.scan()
        #expect(progress.last?.skipped[.noDate] == 1)
        #expect(progress.last?.processed == Fixture.library.count + 1)
        #expect(!harness.service.requestedIDs.contains("undated"))
    }

    /// A revision without a calibrated threshold is an error, not "no duplicates".
    @Test func missingThresholdFailsTheScan() async {
        let harness = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            clusteringConfig: ClusteringConfig(thresholds: [:])
        )
        let (updates, progress) = await harness.scan()
        #expect(progress.last?.phase == .failed(.missingThreshold(revision: Fixture.revision)))
        #expect(updates == [.finished])
        #expect(await harness.tracker.commitCallCount == 0)
        // The prints computed before the failure are kept.
        #expect(await harness.cache.cachedAssetIDs() == ["s3-a", "s3-b"])
    }

    // MARK: - Resume and reuse

    /// Photos with a valid cached print are not analysed again (resume after a kill).
    @Test func cachedPhotosAreNotAnalysedAgain() async {
        let cache = MockFeaturePrintCache(featurePrints: Array(Fixture.prints[0...3]))
        let harness = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            cache: cache
        )
        let (updates, _) = await harness.scan()
        #expect(Set(harness.service.requestedIDs) == ["s3-a", "s3-b"])
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// A large session saves its new prints every `persistBatchSize` photos, so a killed app loses at most one batch.
    @Test func largeSessionsSavePrintsInBatches() async {
        let photos = (0..<7).map { Fixture.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<7).map { Fixture.print("p\($0)", scene: $0) }
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
        let first = ScanHarness(assets: Fixture.library, service: ScriptedFeaturePrintService(prints: Fixture.prints))
        let (firstUpdates, _) = await first.scan()
        #expect(await first.results.storedResults().count == 3)

        let second = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            cache: first.cache,
            results: first.results
        )
        let (secondUpdates, _) = await second.scan()
        #expect(second.service.requestedIDs.isEmpty)
        #expect(second.clustering.callCount == 0)
        #expect(Fixture.addedIDs(secondUpdates) == Fixture.addedIDs(firstUpdates))
        #expect(Fixture.removedIDs(secondUpdates).isEmpty)
    }

    /// A deleted photo breaks its group: the group is published as removed and its session result is dropped.
    @Test func sessionsThatLostPhotosArePublishedAsRemoved() async {
        let first = ScanHarness(assets: Fixture.library, service: ScriptedFeaturePrintService(prints: Fixture.prints))
        _ = await first.scan()

        let tracker = MockLibraryChangeTracker(report: .changes(LibraryDelta(deleted: ["s2-a"])))
        let second = ScanHarness(
            assets: Fixture.library.filter { $0.id != "s2-a" },
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            cache: first.cache,
            results: first.results,
            tracker: tracker
        )
        let (updates, _) = await second.scan()
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s1-b"])
        #expect(Fixture.removedIDs(updates) == ["s2-b"])
        #expect(await second.results.storedResults().map(\.sessionID).allSatisfy { !$0.hasPrefix("s2-b@") })
        #expect(await second.tracker.commitCallCount == 1)
    }

    /// A new similar photo joins a session: the session is re-clustered, its group replaced under the same ID.
    @Test func aGrownSessionIsReclusteredWithOnlyTheNewPhotoAnalysed() async {
        let first = ScanHarness(assets: Fixture.library, service: ScriptedFeaturePrintService(prints: Fixture.prints))
        _ = await first.scan()

        let newPhoto = Fixture.photo("s1-c", session: 1, second: 2)
        let tracker = MockLibraryChangeTracker(report: .changes(LibraryDelta(inserted: ["s1-c"])))
        let newPrint = Fixture.print("s1-c", scene: 0, jitter: 0.05)
        let second = ScanHarness(
            assets: Fixture.library + [newPhoto],
            service: ScriptedFeaturePrintService(prints: Fixture.prints + [newPrint]),
            cache: first.cache,
            results: first.results,
            tracker: tracker
        )
        let (updates, _) = await second.scan()
        #expect(second.service.requestedIDs == ["s1-c"])
        #expect(second.clustering.callCount == 1)
        #expect(Fixture.added(updates).last?.cluster.assetIDs == ["s1-b", "s1-c", "s1-a"])
        #expect(Fixture.removedIDs(updates).isEmpty, "The same ID is replaced, not removed")
    }

    /// Changing the session config recomputes clusters (stored results are stale) but keeps cached prints.
    @Test func aNewSessionConfigReclustersWithoutNewVision() async {
        let first = ScanHarness(assets: Fixture.library, service: ScriptedFeaturePrintService(prints: Fixture.prints))
        _ = await first.scan()

        let second = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            cache: first.cache,
            results: first.results
        )
        let (updates, _) = await second.scan(sessionConfig: SessionConfig(sessionGap: SessionGapPreset.strict.interval))
        #expect(second.service.requestedIDs.isEmpty)
        #expect(second.clustering.callCount == 3)
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
        let keys = Set(await second.results.storedResults().map(\.resultsKey))
        #expect(keys.count == 1, "Results of the old config are dropped")
    }
}
