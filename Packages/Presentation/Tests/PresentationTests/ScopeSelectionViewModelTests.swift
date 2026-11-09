import Domain
import DomainTestSupport
import Foundation
import Presentation
import Testing

@MainActor
struct ScopeSelectionViewModelTests {
    /// Collects the values passed to `onApply`.
    @MainActor
    private final class ApplyRecorder {
        var applied: [ScopePreferences] = []
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            fatalError("Invalid test date")
        }
        return date
    }

    private static let now = day(2026, 11, 8).addingTimeInterval(15 * 3_600)

    private static let albums = [
        AlbumSummary(id: "recents", title: "Recents", kind: .recents, estimatedCount: 10),
        AlbumSummary(id: "favorites", title: "Favorites", kind: .favorites, estimatedCount: 2),
        AlbumSummary(id: "trip", title: "Trip", kind: .user, estimatedCount: 3),
        AlbumSummary(id: "family", title: "Family", kind: .user, estimatedCount: 2)
    ]

    private static func asset(_ id: String, minutesAgo: Double) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: now.addingTimeInterval(-minutesAgo * 60),
            pixelWidth: 100,
            pixelHeight: 100,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    /// A library where `shared` is in both user albums.
    private static func makeLibrary() -> MockPhotoLibraryRepository {
        MockPhotoLibraryRepository(
            assets: [
                asset("shared", minutesAgo: 1),
                asset("trip-only", minutesAgo: 2),
                asset("family-only", minutesAgo: 3)
            ],
            albumMembers: [
                "trip": ["shared", "trip-only"],
                "family": ["shared", "family-only"]
            ],
            albumSummaries: albums
        )
    }

    private func makeViewModel(
        library: MockPhotoLibraryRepository? = nil,
        store: MockScopePreferencesStore? = nil,
        recorder: ApplyRecorder? = nil,
        access: PhotoLibraryAuthorization = .authorized,
        calendar: Calendar? = nil,
        countDebounce: Duration = .zero
    ) -> ScopeSelectionViewModel {
        let recorder = recorder ?? ApplyRecorder()
        // Copy the main-actor static into a local: the `now` closure is @Sendable.
        let fixedNow = Self.now
        return ScopeSelectionViewModel(
            library: library ?? Self.makeLibrary(),
            permissions: MockPhotoPermissionService(status: access),
            store: store ?? MockScopePreferencesStore(),
            onApply: { recorder.applied.append($0) },
            now: { fixedNow },
            calendar: calendar ?? Self.calendar,
            countDebounce: countDebounce
        )
    }

    @Test func defaultsToAllPhotosWithScreenshotsSkipped() async {
        let store = MockScopePreferencesStore()
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.isLoaded)
        #expect(viewModel.isAllPhotos)
        #expect(viewModel.excludeScreenshots)
        #expect(viewModel.datePreset == .anyTime)
        #expect(viewModel.preferences == .default)
        #expect(await store.savedPreferences.isEmpty)
    }

    @Test func recentsIsNotListedBecauseItIsAllPhotos() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        #expect(viewModel.smartAlbums.map(\.id) == ["favorites"])
        #expect(viewModel.userAlbums.map(\.id) == ["trip", "family"])
    }

    @Test func albumsDeletedOutsideTheAppAreDroppedAndTheCleanedScopeIsSaved() async {
        let store = MockScopePreferencesStore(preferences: ScopePreferences(albumIDs: ["gone", "trip"]))
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.selectedAlbumIDs == ["trip"])
        #expect(await store.savedPreferences == [ScopePreferences(albumIDs: ["trip"])])
    }

    @Test func whenEverySelectedAlbumIsGoneTheScopeFallsBackToAllPhotos() async {
        let store = MockScopePreferencesStore(preferences: ScopePreferences(albumIDs: ["gone"]))
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.isAllPhotos)
        #expect(await store.savedPreferences == [.default])
    }

    @Test func duplicateAlbumIDsAreCollapsedInListOrder() async {
        let store = MockScopePreferencesStore(preferences: ScopePreferences(albumIDs: ["family", "trip", "family"]))
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.preferences.albumIDs == ["trip", "family"])
    }

    @Test func deselectingTheLastAlbumGoesBackToAllPhotos() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.toggle("trip")
        #expect(viewModel.isSelected("trip"))
        #expect(!viewModel.isAllPhotos)
        viewModel.toggle("trip")
        #expect(viewModel.isAllPhotos)
        #expect(viewModel.preferences.albumIDs == nil)
    }

    @Test func selectAllPhotosClearsTheAlbumSelection() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.toggle("trip")
        viewModel.toggle("favorites")
        viewModel.selectAllPhotos()
        #expect(viewModel.isAllPhotos)
    }

    @Test func countsPhotosForTheCurrentChoice() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        await viewModel.waitForPendingCount()
        #expect(viewModel.estimatedCount == 3)
        #expect(!viewModel.isCounting)

        viewModel.toggle("trip")
        await viewModel.waitForPendingCount()
        #expect(viewModel.estimatedCount == 2)
    }

    @Test func rapidChangesAreDebouncedIntoOneCountForTheLastChoice() async {
        let library = Self.makeLibrary()
        let viewModel = makeViewModel(library: library, countDebounce: .milliseconds(50))
        await viewModel.load()
        viewModel.toggle("trip")
        viewModel.toggle("family")
        viewModel.setExcludeScreenshots(false)
        await viewModel.waitForPendingCount()

        #expect(await library.assetCountCallCount == 1)
        let expected = ScanScope(albumIDs: ["trip", "family"], excludeScreenshots: false)
        #expect(await library.requestedScopes.last == expected)
    }

    @Test func applySavesAndReportsTheChoice() async {
        let store = MockScopePreferencesStore()
        let recorder = ApplyRecorder()
        let viewModel = makeViewModel(store: store, recorder: recorder)
        await viewModel.load()
        viewModel.toggle("family")
        viewModel.toggle("favorites")
        viewModel.setDatePreset(.last30Days)
        viewModel.setExcludeScreenshots(false)
        await viewModel.apply()

        let expected = ScopePreferences(
            albumIDs: ["favorites", "family"],
            dateFilter: .last30Days,
            excludeScreenshots: false
        )
        #expect(await store.preferences == expected)
        #expect(recorder.applied == [expected])
    }

    @Test func applyKeepsTheHiddenBurstSetting() async {
        let store = MockScopePreferencesStore(preferences: ScopePreferences(includeBursts: true))
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        await viewModel.apply()
        #expect(await store.preferences.includeBursts)
    }

    @Test func customRangeCoversWholeDaysAndKeepsStartBeforeEnd() async {
        let viewModel = makeViewModel()
        await viewModel.load()
        viewModel.setDatePreset(.custom)
        viewModel.setCustomStart(Self.day(2026, 6, 1))
        viewModel.setCustomEnd(Self.day(2026, 6, 3))
        guard case .custom(let range) = viewModel.preferences.dateFilter else {
            Issue.record("Expected a custom date filter")
            return
        }
        #expect(range.lowerBound == Self.day(2026, 6, 1))
        #expect(range.contains(Self.day(2026, 6, 4).addingTimeInterval(-0.001)))
        #expect(!range.contains(Self.day(2026, 6, 4)))

        viewModel.setCustomStart(Self.day(2026, 6, 10))
        #expect(viewModel.customEnd == Self.day(2026, 6, 10))
        viewModel.setCustomEnd(Self.day(2026, 6, 5))
        #expect(viewModel.customStart == Self.day(2026, 6, 5))
    }

    @Test func savedCustomRangeIsRestored() async {
        let range = Self.day(2026, 3, 1)...Self.day(2026, 3, 8).addingTimeInterval(-1)
        let store = MockScopePreferencesStore(preferences: ScopePreferences(dateFilter: .custom(range)))
        let viewModel = makeViewModel(store: store)
        await viewModel.load()
        #expect(viewModel.datePreset == .custom)
        #expect(viewModel.customStart == Self.day(2026, 3, 1))
        #expect(viewModel.customEnd == Self.day(2026, 3, 7))
        #expect(viewModel.preferences.dateFilter == .custom(range))
        #expect(await store.savedPreferences.isEmpty)
    }

    @Test func savedCustomRangeIsKeptExactlyInAnotherTimeZone() async throws {
        let range = Self.day(2026, 3, 1)...Self.day(2026, 3, 8).addingTimeInterval(-0.5)
        let store = MockScopePreferencesStore(preferences: ScopePreferences(dateFilter: .custom(range)))
        var tokyo = Self.calendar
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let viewModel = makeViewModel(store: store, calendar: tokyo)
        await viewModel.load()
        #expect(viewModel.preferences.dateFilter == .custom(range))
        #expect(await store.savedPreferences.isEmpty)
    }

    @Test func underLimitedAccessUnlistedAlbumsAreKeptNotDropped() async {
        let store = MockScopePreferencesStore(preferences: ScopePreferences(albumIDs: ["hidden", "trip"]))
        let viewModel = makeViewModel(store: store, access: .limited)
        await viewModel.load()
        #expect(viewModel.selectedAlbumIDs == ["trip"])
        #expect(!viewModel.isAllPhotos)
        #expect(viewModel.preferences.albumIDs == ["trip", "hidden"])
        #expect(await store.savedPreferences.isEmpty)

        viewModel.selectAllPhotos()
        #expect(viewModel.isAllPhotos)
        #expect(viewModel.preferences.albumIDs == nil)
    }

    @Test func aSlowerOlderCountNeverOverwritesANewerOne() async throws {
        let library = Self.makeLibrary()
        let viewModel = makeViewModel(library: library)
        await library.holdNextAssetCount()
        await viewModel.load()
        var waits = 0
        while !(await library.isHoldingAssetCount) {
            waits += 1
            try #require(waits < 1_000)
            await Task.yield()
        }

        viewModel.toggle("trip")
        await viewModel.waitForPendingCount()
        #expect(viewModel.estimatedCount == 2)

        await library.releaseHeldAssetCount()
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(viewModel.estimatedCount == 2)
        #expect(!viewModel.isCounting)
    }

    @Test func dismissingTheSheetCancelsAPendingCount() async {
        let library = Self.makeLibrary()
        let viewModel = makeViewModel(library: library, countDebounce: .milliseconds(50))
        await viewModel.load()
        viewModel.cancelPendingCount()
        await viewModel.waitForPendingCount()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await library.assetCountCallCount == 0)
        #expect(!viewModel.isCounting)
    }

    @Test func photoInSeveralSelectedAlbumsIsScannedOnce() async throws {
        let library = Self.makeLibrary()
        let viewModel = makeViewModel(library: library)
        await viewModel.load()
        viewModel.toggle("trip")
        viewModel.toggle("family")

        let scope = viewModel.preferences.scanScope(now: Self.now, calendar: Self.calendar)
        var ids: [String] = []
        for try await page in library.assetPages(scope: scope, pageSize: 10) {
            ids += page.map(\.id)
        }
        #expect(ids == ["shared", "trip-only", "family-only"])
    }
}
