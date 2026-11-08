import Domain
import Foundation
import Testing

struct ScanScopeTests {
    @Test func defaultsScanWholeLibraryWithoutScreenshotsOrBurstFrames() {
        let scope = ScanScope.allPhotos
        #expect(scope.albumIDs == nil)
        #expect(scope.dateRange == nil)
        #expect(scope.excludeScreenshots)
        #expect(!scope.includeBursts)
    }

    @Test func survivesCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let scope = ScanScope(
            albumIDs: ["album-1", "album-2"],
            dateRange: start...start.addingTimeInterval(86_400),
            excludeScreenshots: false,
            includeBursts: true
        )
        let decoded = try JSONDecoder().decode(ScanScope.self, from: JSONEncoder().encode(scope))
        #expect(decoded == scope)
    }

    @Test func albumSummariesCompareByValue() {
        let lhs = AlbumSummary(id: "A", title: "Trip", kind: .user, estimatedCount: 3)
        #expect(lhs == AlbumSummary(id: "A", title: "Trip", kind: .user, estimatedCount: 3))
        #expect(lhs != AlbumSummary(id: "A", title: "Trip", kind: .user, estimatedCount: 4))
    }
}
