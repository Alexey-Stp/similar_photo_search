import Foundation

extension ScanViewModel {
    /// Every photo has been counted but the scan is still saving its results and the library's change token, which
    /// can take a few seconds on a large library. The screen shows "Finishing…" with a spinner instead of a ring that
    /// looks frozen at 100 %.
    public var isFinishing: Bool {
        guard isScanning, let progress, progress.total > 0 else { return false }
        return progress.processed >= progress.total
    }
}
