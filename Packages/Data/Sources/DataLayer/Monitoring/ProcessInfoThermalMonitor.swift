import Domain
import Foundation

/// `ThermalMonitor` over `ProcessInfo`: the thermal state and Low Power Mode, updated from
/// `ProcessInfo.thermalStateDidChangeNotification` and `NSProcessInfoPowerStateDidChange`.
///
/// The notifications arrive on arbitrary threads; the callback only reads the new conditions and yields them to the
/// open streams (once per actual change). Neither API is a required-reason API.
public final class ProcessInfoThermalMonitor: ThermalMonitor, @unchecked Sendable {
    // @unchecked: `last` and `continuations` are guarded by `lock`; `refreshLock` serializes `refresh()`;
    // the rest is immutable.
    private let readConditions: @Sendable () -> ScanConditions
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private let refreshLock = NSLock()
    private var observers: [any NSObjectProtocol] = []
    private var last: ScanConditions
    private var continuations: [UInt64: AsyncStream<ScanConditions>.Continuation] = [:]
    private var nextID: UInt64 = 0

    /// Creates a monitor and starts observing.
    /// - Parameters:
    ///   - notificationCenter: Where the two notifications are posted; `.default` in the app.
    ///   - readConditions: Reads the current conditions; `ProcessInfo.processInfo` in the app (tests inject values).
    public init(
        notificationCenter: NotificationCenter = .default,
        readConditions: @escaping @Sendable () -> ScanConditions = ProcessInfoThermalMonitor.processInfoConditions
    ) {
        self.notificationCenter = notificationCenter
        self.readConditions = readConditions
        self.last = readConditions()
        let names = [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange]
        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    /// Stops observing and ends every stream.
    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// The conditions right now. Doesn't touch the change tracking, so open streams still get every change.
    public func currentConditions() async -> ScanConditions {
        readConditions()
    }

    /// A new stream of changes.
    public func conditionChanges() -> AsyncStream<ScanConditions> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ScanConditions.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = lock.withLock {
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeStream(id)
        }
        return stream
    }

    /// Reads the conditions and yields them if they changed.
    ///
    /// Notifications can arrive on several threads at once: `refreshLock` serializes read and publication, so an
    /// older reading is never published after a newer one. The yields happen outside `lock`, which `removeStream`
    /// takes when a stream ends, so a stream terminating during a yield cannot deadlock.
    private func refresh() {
        refreshLock.withLock {
            let conditions = readConditions()
            let open: [AsyncStream<ScanConditions>.Continuation] = lock.withLock {
                guard conditions != last else { return [] }
                last = conditions
                return Array(continuations.values)
            }
            for continuation in open {
                continuation.yield(conditions)
            }
        }
    }

    /// Forgets the continuation of a stream whose consumer has stopped.
    private func removeStream(_ id: UInt64) {
        lock.withLock { continuations[id] = nil }
    }

    /// The conditions as `ProcessInfo.processInfo` reports them.
    @Sendable
    public static func processInfoConditions() -> ScanConditions {
        let info = ProcessInfo.processInfo
        return ScanConditions(thermalLevel: level(info.thermalState), isLowPowerModeEnabled: info.isLowPowerModeEnabled)
    }

    /// Maps `ProcessInfo.ThermalState`; an unknown future state counts as `.serious` (slow, but not paused).
    public static func level(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}
