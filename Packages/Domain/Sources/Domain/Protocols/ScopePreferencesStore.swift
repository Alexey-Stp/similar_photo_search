import Foundation

/// Saves the user's scan scope between launches.
///
/// Stores only local app preferences; nothing leaves the device.
public protocol ScopePreferencesStore: Sendable {
    /// The saved preferences, or `ScopePreferences.default` if nothing was saved or the saved value can't be read.
    func load() async -> ScopePreferences

    /// Replaces the saved preferences.
    func save(_ preferences: ScopePreferences) async
}
