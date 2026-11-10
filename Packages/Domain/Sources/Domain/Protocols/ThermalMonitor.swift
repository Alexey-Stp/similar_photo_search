import Foundation

/// Reports the device conditions a scan must adapt to: the thermal state and Low Power Mode.
///
/// The scan derives its width from them with `ScanConditions.recommendedConcurrency(fullConcurrency:)`.
public protocol ThermalMonitor: Sendable {
    /// The conditions right now.
    func currentConditions() async -> ScanConditions

    /// A new stream that yields the conditions every time they change (not the current value). Each call returns
    /// its own stream; it ends when the consumer stops iterating.
    func conditionChanges() -> AsyncStream<ScanConditions>
}
