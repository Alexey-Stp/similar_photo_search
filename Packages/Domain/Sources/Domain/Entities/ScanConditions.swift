import Foundation

/// The device's thermal state, as `ProcessInfo.ThermalState` reports it, without depending on it.
public enum ThermalLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Normal temperature.
    case nominal
    /// Slightly warm; full speed is still fine.
    case fair
    /// Hot: the scan runs one photo at a time.
    case serious
    /// Very hot: the scan pauses until the device cools down.
    case critical

    /// Orders levels from cool to hot.
    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the device allows the scan to do right now: its thermal state and whether Low Power Mode is on.
public struct ScanConditions: Sendable, Hashable {
    /// Width of the image work when Low Power Mode is on (and the device is not hot).
    public static let lowPowerConcurrency = 2

    /// The thermal state.
    public var thermalLevel: ThermalLevel
    /// Whether the user turned on Low Power Mode.
    public var isLowPowerModeEnabled: Bool

    /// Creates conditions.
    public init(thermalLevel: ThermalLevel = .nominal, isLowPowerModeEnabled: Bool = false) {
        self.thermalLevel = thermalLevel
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    /// A cool device on mains power.
    public static let nominal = ScanConditions()

    /// Whether the scan must pause until the device cools down (`.critical`).
    public var isPaused: Bool { thermalLevel == .critical }

    /// How many photos may be analysed at the same time.
    ///
    /// `nominal`/`fair`: `fullConcurrency`; Low Power Mode: at most `lowPowerConcurrency`; `serious`: 1;
    /// `critical`: 0, which means pause. Never above `fullConcurrency`, which is treated as at least 1.
    public func recommendedConcurrency(fullConcurrency: Int) -> Int {
        let full = max(1, fullConcurrency)
        switch thermalLevel {
        case .critical:
            return 0
        case .serious:
            return 1
        case .nominal, .fair:
            return isLowPowerModeEnabled ? min(full, Self.lowPowerConcurrency) : full
        }
    }
}
