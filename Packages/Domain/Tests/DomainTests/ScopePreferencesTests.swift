import Domain
import DomainTestSupport
import Foundation
import Testing

struct ScopePreferencesTests {
    /// A fixed Gregorian calendar in UTC, so results don't depend on the machine's time zone.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else {
            fatalError("Invalid test date")
        }
        return date
    }

    @Test func defaultScansWholeLibraryAtAnyDateWithoutScreenshots() {
        let scope = ScopePreferences.default.scanScope(now: Self.date(2026, 11, 8), calendar: Self.calendar)
        #expect(scope == ScanScope.allPhotos)
    }

    @Test func anyTimeHasNoRange() {
        #expect(DateFilter.anyTime.range(now: Self.date(2026, 11, 8), calendar: Self.calendar) == nil)
    }

    @Test func last30DaysStartsAtMidnight29DaysBeforeToday() {
        let now = Self.date(2026, 11, 8, 15, 30)
        let range = DateFilter.last30Days.range(now: now, calendar: Self.calendar)
        #expect(range == Self.date(2026, 10, 10)...now)
    }

    @Test func thisYearStartsOnJanuaryFirst() {
        let now = Self.date(2026, 11, 8, 15, 30)
        #expect(DateFilter.thisYear.range(now: now, calendar: Self.calendar) == Self.date(2026, 1, 1)...now)
    }

    @Test func thisYearStartsOnJanuaryFirstEvenWithANonGregorianCalendar() {
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = Self.calendar.timeZone
        let now = Self.date(2026, 11, 8, 15, 30)
        #expect(DateFilter.thisYear.range(now: now, calendar: hebrew) == Self.date(2026, 1, 1)...now)
    }

    @Test func thisYearOnNewYearsMidnightIsASingleInstant() {
        let now = Self.date(2027, 1, 1)
        #expect(DateFilter.thisYear.range(now: now, calendar: Self.calendar) == now...now)
    }

    @Test func customRangeIsUsedAsIs() {
        let range = Self.date(2025, 6, 1)...Self.date(2025, 6, 14, 23, 59)
        #expect(DateFilter.custom(range).range(now: Self.date(2026, 11, 8), calendar: Self.calendar) == range)
    }

    @Test func scanScopeCarriesEveryField() {
        let now = Self.date(2026, 11, 8, 12)
        let preferences = ScopePreferences(
            albumIDs: ["album-1"],
            dateFilter: .thisYear,
            excludeScreenshots: false,
            includeBursts: true
        )
        let scope = preferences.scanScope(now: now, calendar: Self.calendar)
        #expect(scope.albumIDs == ["album-1"])
        #expect(scope.dateRange == Self.date(2026, 1, 1)...now)
        #expect(!scope.excludeScreenshots)
        #expect(scope.includeBursts)
    }

    @Test(arguments: [
        DateFilter.anyTime,
        .last30Days,
        .thisYear,
        .custom(Date(timeIntervalSince1970: 1_700_000_000)...Date(timeIntervalSince1970: 1_700_086_400))
    ])
    func survivesCodableRoundTrip(filter: DateFilter) throws {
        let preferences = ScopePreferences(albumIDs: ["a", "b"], dateFilter: filter, excludeScreenshots: false)
        let decoded = try JSONDecoder().decode(ScopePreferences.self, from: JSONEncoder().encode(preferences))
        #expect(decoded == preferences)
    }

    @Test func mockStoreReturnsWhatWasSaved() async {
        let store = MockScopePreferencesStore()
        #expect(await store.load() == .default)
        let preferences = ScopePreferences(albumIDs: ["x"], dateFilter: .last30Days)
        await store.save(preferences)
        #expect(await store.load() == preferences)
        #expect(await store.savedPreferences == [preferences])
        #expect(await store.loadCallCount == 2)
    }
}
