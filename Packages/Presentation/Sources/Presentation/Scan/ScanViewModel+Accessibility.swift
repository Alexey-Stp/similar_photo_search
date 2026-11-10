import Foundation

extension ScanViewModel {
    /// The progress for VoiceOver (`.accessibilityValue`), rounded down to steps of 10 %, so it changes at most ten
    /// times per scan instead of with every snapshot: "40 %".
    public var accessibilityProgressText: String {
        Self.accessibilityPercent(of: progress?.fractionCompleted ?? 0)
            .formatted(.percent.precision(.fractionLength(0)))
    }

    /// `fraction` rounded down to a multiple of 0.1 (1 stays 1).
    private static func accessibilityPercent(of fraction: Double) -> Double {
        let clamped = min(1, max(0, fraction))
        return (clamped * 10 + 1e-9).rounded(.down) / 10
    }
}
