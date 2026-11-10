import DataLayer
import Domain
import Foundation
import Testing

struct ProcessInfoThermalMonitorTests {
    /// Conditions a test can change between notifications.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ScanConditions
        init(_ value: ScanConditions) { self.value = value }
        func get() -> ScanConditions { lock.withLock { value } }
        func set(_ newValue: ScanConditions) { lock.withLock { value = newValue } }
    }

    @Test func mapsEveryThermalState() {
        #expect(ProcessInfoThermalMonitor.level(.nominal) == .nominal)
        #expect(ProcessInfoThermalMonitor.level(.fair) == .fair)
        #expect(ProcessInfoThermalMonitor.level(.serious) == .serious)
        #expect(ProcessInfoThermalMonitor.level(.critical) == .critical)
    }

    @Test func currentConditionsAreRead() async {
        let box = Box(ScanConditions(thermalLevel: .fair, isLowPowerModeEnabled: true))
        let monitor = ProcessInfoThermalMonitor(notificationCenter: NotificationCenter(), readConditions: box.get)
        #expect(await monitor.currentConditions() == ScanConditions(thermalLevel: .fair, isLowPowerModeEnabled: true))
    }

    /// Both notifications publish the new conditions; a notification without a change publishes nothing.
    @Test func notificationsPublishChanges() async {
        let center = NotificationCenter()
        let box = Box(.nominal)
        let monitor = ProcessInfoThermalMonitor(notificationCenter: center, readConditions: box.get)
        var iterator = monitor.conditionChanges().makeAsyncIterator()

        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        box.set(ScanConditions(thermalLevel: .critical))
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        #expect(await iterator.next() == ScanConditions(thermalLevel: .critical))

        box.set(ScanConditions(thermalLevel: .critical, isLowPowerModeEnabled: true))
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(await iterator.next() == ScanConditions(thermalLevel: .critical, isLowPowerModeEnabled: true))
    }

    @Test func theRealProcessInfoCanBeRead() {
        let conditions = ProcessInfoThermalMonitor.processInfoConditions()
        #expect(ThermalLevel.allCases.contains(conditions.thermalLevel))
    }
}
