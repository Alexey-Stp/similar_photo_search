import Domain
import DomainTestSupport
import Foundation
import Testing

/// Thermal state, Low Power Mode and progress throttling.
struct AnalysisCoordinatorThrottlingTests {
    typealias Fixture = ScanFixture

    // MARK: - Throttling

    /// Nominal conditions use the full width; `.serious` drops it to one photo at a time.
    @Test func seriousThermalStateDropsConcurrencyToOne() async {
        let manyPhotos = (0..<12).map { Fixture.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<12).map { Fixture.print("p\($0)", scene: 0) }

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
        let manyPhotos = (0..<12).map { Fixture.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<12).map { Fixture.print("p\($0)", scene: 0) }
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
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            thermal: thermal
        )
        let streams = await harness.start()
        let collected = Task { await Fixture.collect(streams) }
        #expect(await eventually { thermal.subscriberCount > 0 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(harness.service.requestedIDs.isEmpty, "Nothing is analysed while critical")

        thermal.set(ScanConditions(thermalLevel: .fair))
        let (updates, progress) = await collected.value
        #expect(progress.contains { $0.phase == .throttled })
        #expect(progress.last?.phase == .done)
        #expect(Fixture.addedIDs(updates) == ["s3-b", "s2-b", "s1-b"])
    }

    /// Cancel works while the scan is paused.
    @Test func cancelEndsAPausedScan() async {
        let thermal = MockThermalMonitor(conditions: ScanConditions(thermalLevel: .critical))
        let harness = ScanHarness(
            assets: Fixture.library,
            service: ScriptedFeaturePrintService(prints: Fixture.prints),
            thermal: thermal
        )
        let streams = await harness.start()
        let collected = Task { await Fixture.collect(streams) }
        #expect(await eventually { thermal.subscriberCount > 0 })
        try? await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.cancel()
        let (_, progress) = await collected.value
        #expect(progress.last?.phase == .cancelled)
    }

    // MARK: - Progress

    /// With the default interval, a burst of work publishes far fewer snapshots than photos.
    @Test func progressIsThrottled() async {
        let manyPhotos = (0..<200).map { Fixture.photo("p\($0)", session: 1, second: $0) }
        let prints = (0..<200).map { Fixture.print("p\($0)", scene: $0 % 4) }
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
