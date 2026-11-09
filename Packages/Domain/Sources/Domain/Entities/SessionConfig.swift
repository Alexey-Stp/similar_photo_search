import Foundation

/// How the library is cut into shooting sessions.
///
/// Changing the config changes which photos are compared, so clusters must be recomputed. Feature prints don't
/// depend on it and stay cached.
public struct SessionConfig: Sendable, Hashable {
    /// The largest gap between neighbouring shots that still keeps them in one session, in seconds.
    public var sessionGap: TimeInterval
    /// The largest number of photos in one session. Bigger runs are split at their largest internal gap.
    public var maxSessionSize: Int

    /// Creates a config. A negative `sessionGap` is treated as 0, a `maxSessionSize` below 1 as 1.
    public init(sessionGap: TimeInterval = SessionGapPreset.balanced.interval, maxSessionSize: Int = 500) {
        self.sessionGap = max(0, sessionGap)
        self.maxSessionSize = max(1, maxSessionSize)
    }

    /// Balanced gap (15 min), at most 500 photos per session.
    public static let `default` = SessionConfig()
}

/// The session gap choices offered in Settings.
public enum SessionGapPreset: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// 5 minutes: only quick series are compared.
    case strict
    /// 15 minutes, the default.
    case balanced
    /// 60 minutes: slow series (a sunset, a long portrait session) stay together.
    case relaxed

    /// The gap in seconds.
    public var interval: TimeInterval {
        switch self {
        case .strict: 5 * 60
        case .balanced: 15 * 60
        case .relaxed: 60 * 60
        }
    }

    /// Stable identity for `ForEach` and `Picker`.
    public var id: String { rawValue }
}
