import Foundation

/// Keeps the screen awake. The app implements it with `UIApplication.isIdleTimerDisabled`.
@MainActor
public protocol IdleTimerControlling: AnyObject {
    /// Disables (or re-enables) the automatic screen lock.
    func setIdleTimerDisabled(_ disabled: Bool)
}

/// An opaque handle of a running background task.
public struct BackgroundTaskToken: Hashable, Sendable {
    /// The raw identifier (`UIBackgroundTaskIdentifier.rawValue` in the app).
    public let rawValue: Int

    /// Creates a token.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Asks the system for extra time after the app goes to the background. The app implements it with
/// `UIApplication.beginBackgroundTask(withName:expirationHandler:)`.
@MainActor
public protocol BackgroundTaskRunning: AnyObject {
    /// Starts a background task; `expiration` runs on the main actor when the granted time is up and must return
    /// quickly. Returns `nil` if the system grants no time.
    func beginBackgroundTask(
        named name: String,
        expiration: @escaping @MainActor @Sendable () -> Void
    ) -> BackgroundTaskToken?

    /// Ends a background task. Must be called for every token, also from `expiration`.
    func endBackgroundTask(_ token: BackgroundTaskToken)
}
