import DataLayer
import Domain
import Foundation
import Testing

struct UserDefaultsScopePreferencesStoreTests {
    /// A throwaway defaults suite, so tests never touch the real app defaults or each other.
    private static func makeDefaults() throws -> UserDefaults {
        let suite = "UserDefaultsScopePreferencesStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func emptyStoreLoadsDefault() async throws {
        let store = UserDefaultsScopePreferencesStore(defaults: try Self.makeDefaults())
        #expect(await store.load() == .default)
    }

    @Test func savedPreferencesSurviveANewStoreInstance() async throws {
        let defaults = try Self.makeDefaults()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let preferences = ScopePreferences(
            albumIDs: ["album-1", "album-2"],
            dateFilter: .custom(start...start.addingTimeInterval(86_400)),
            excludeScreenshots: false,
            includeBursts: true
        )
        await UserDefaultsScopePreferencesStore(defaults: defaults).save(preferences)
        #expect(await UserDefaultsScopePreferencesStore(defaults: defaults).load() == preferences)
    }

    @Test func unreadableDataLoadsDefault() async throws {
        let defaults = try Self.makeDefaults()
        defaults.set(Data("not json".utf8), forKey: UserDefaultsScopePreferencesStore.key)
        let store = UserDefaultsScopePreferencesStore(defaults: defaults)
        #expect(await store.load() == .default)
    }
}
