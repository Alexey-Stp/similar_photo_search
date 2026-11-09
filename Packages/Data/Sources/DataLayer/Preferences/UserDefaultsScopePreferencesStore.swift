import Domain
import Foundation
import os

/// `ScopePreferencesStore` that keeps the scan scope as JSON in `UserDefaults`.
///
/// Uses the app's own defaults only (required-reason API `UserDefaults`, reason CA92.1 in the privacy manifest).
/// `UserDefaults` is thread-safe, so the store can be shared across actors.
public final class UserDefaultsScopePreferencesStore: ScopePreferencesStore, @unchecked Sendable {
    /// The defaults key the scope is stored under.
    public static let key = "scanScope"

    private static let logger = Logger(subsystem: "com.similarphotos", category: "preferences")

    private let defaults: UserDefaults

    /// Creates the store.
    /// - Parameter defaults: Where the scope is kept. The app passes `.standard`; tests pass a throwaway suite.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The saved scope, or `.default` if none was saved or it can't be decoded (for example after a format change).
    public func load() async -> ScopePreferences {
        guard let data = defaults.data(forKey: Self.key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(ScopePreferences.self, from: data)
        } catch {
            Self.logger.warning("Saved scan scope is unreadable; using the default scope")
            return .default
        }
    }

    /// Saves the scope as JSON. An encoding failure is logged and leaves the previous value in place.
    public func save(_ preferences: ScopePreferences) async {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: Self.key)
        } catch {
            Self.logger.error("Could not encode the scan scope")
        }
    }
}
