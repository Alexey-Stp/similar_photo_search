import Presentation
import UIKit

/// The idle timer and background tasks of `UIApplication`, for the scan (SPS-14).
@MainActor
final class UIKitAppLifecycle: IdleTimerControlling, BackgroundTaskRunning {
    /// Disables or re-enables the automatic screen lock.
    func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }

    /// Starts a background task; `nil` if the system grants no time.
    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken? {
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // UIKit calls the expiration handler on the main thread.
            MainActor.assumeIsolated { expiration() }
        }
        guard identifier != .invalid else { return nil }
        return BackgroundTaskToken(rawValue: identifier.rawValue)
    }

    /// Ends a background task.
    func endBackgroundTask(_ token: BackgroundTaskToken) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token.rawValue))
    }
}
