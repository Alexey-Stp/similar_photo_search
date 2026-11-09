import Domain
import Foundation

/// In-memory `ScopePreferencesStore` for tests.
public actor MockScopePreferencesStore: ScopePreferencesStore {
    /// The value returned by `load()`. `save(_:)` replaces it.
    public private(set) var preferences: ScopePreferences
    /// Every value passed to `save(_:)`, in call order.
    public private(set) var savedPreferences: [ScopePreferences] = []
    /// Number of `load()` calls.
    public private(set) var loadCallCount = 0

    /// Creates the mock with the value `load()` returns first.
    public init(preferences: ScopePreferences = .default) {
        self.preferences = preferences
    }

    /// Returns `preferences`.
    public func load() -> ScopePreferences {
        loadCallCount += 1
        return preferences
    }

    /// Records the value and makes it the one `load()` returns.
    public func save(_ preferences: ScopePreferences) {
        savedPreferences.append(preferences)
        self.preferences = preferences
    }
}
