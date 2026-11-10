import Domain
import DomainTestSupport
import Foundation
import Testing

struct MockPhotoLibraryRepositoryTests {
    private struct PageError: Error {}

    private func asset(
        _ id: String,
        _ seconds: TimeInterval?,
        screenshot: Bool = false,
        burst: String? = nil
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: seconds.map { Date(timeIntervalSince1970: $0) },
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: screenshot ? [.screenshot] : [],
            burstIdentifier: burst
        )
    }

    private func collect(_ stream: AsyncThrowingStream<[PhotoAsset], Error>) async throws -> [[PhotoAsset]] {
        var pages: [[PhotoAsset]] = []
        for try await page in stream {
            pages.append(page)
        }
        return pages
    }

    @Test func assetsByIDKeepLibraryOrderAndLeaveOutMissingIDs() async {
        let repository = MockPhotoLibraryRepository(assets: [asset("old", 10), asset("new", 20), asset("mid", 15)])
        let found = await repository.assets(withIDs: ["old", "gone", "new", "old"])
        #expect(found.map(\.id) == ["new", "old"])
        #expect(await repository.assetsByIDCallCount == 1)
    }

    @Test func emptyLibraryYieldsNoPages() async throws {
        let repository = MockPhotoLibraryRepository()
        #expect(await repository.assetCount(scope: .allPhotos) == 0)
        #expect(try await collect(repository.assetPages(scope: .allPhotos, pageSize: 10)).isEmpty)
    }

    @Test func pagesFollowLibraryOrder() async throws {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("a", 1), asset("b", 3), asset("c", nil), asset("d", 2)]
        )
        let pages = try await collect(repository.assetPages(scope: .allPhotos, pageSize: 3))
        #expect(pages.map { $0.map(\.id) } == [["b", "d", "a"], ["c"]])
    }

    @Test func scopeFiltersScreenshotsDatesAndAlbums() async throws {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("a", 10), asset("shot", 20, screenshot: true), asset("b", 30), asset("undated", nil)],
            albumMembers: ["x": ["a", "b"], "y": ["b", "shot"]]
        )
        let range = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 25)
        #expect(await repository.assetCount(scope: ScanScope(dateRange: range)) == 1)
        #expect(await repository.assetCount(scope: ScanScope(excludeScreenshots: false)) == 4)
        let albums = ScanScope(albumIDs: ["x", "y"], excludeScreenshots: false)
        let pages = try await collect(repository.assetPages(scope: albums, pageSize: 10))
        #expect(pages.flatMap { $0 }.map(\.id) == ["b", "shot", "a"])
    }

    @Test func countAddsEachSelectedAlbumButPagesDeliverSharedAssetsOnce() async throws {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("a", 3), asset("shared", 2), asset("b", 1)],
            albumMembers: ["x": ["a", "shared"], "y": ["shared", "b"]]
        )
        let scope = ScanScope(albumIDs: ["x", "y", "x"])
        #expect(await repository.assetCount(scope: scope) == 4)
        let pages = try await collect(repository.assetPages(scope: scope, pageSize: 10))
        #expect(pages.flatMap { $0 }.map(\.id) == ["a", "shared", "b"])
    }

    @Test func burstsKeepOneRepresentativeUnlessIncluded() async {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("b1", 3, burst: "B"), asset("b2", 2, burst: "B"), asset("single", 1)]
        )
        #expect(await repository.assetCount(scope: ScanScope(includeBursts: false)) == 2)
        #expect(await repository.assetCount(scope: ScanScope(includeBursts: true)) == 3)
    }

    @Test func pagesKeepEqualTimestampsTogetherAndStartUndatedOnANewPage() async throws {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("new", 5), asset("t-b", 4), asset("t-a", 4), asset("old", 3), asset("undated", nil)]
        )
        let pages = try await collect(repository.assetPages(scope: .allPhotos, pageSize: 2))
        #expect(pages.map { $0.map(\.id) } == [["new", "t-a", "t-b"], ["old"], ["undated"]])
    }

    @Test func injectedFailureEndsTheStreamAfterEarlierPages() async {
        let repository = MockPhotoLibraryRepository(
            assets: [asset("a", 3), asset("b", 2), asset("c", 1)],
            pageFailure: (afterPages: 1, error: PageError())
        )
        var received: [[PhotoAsset]] = []
        var thrown: (any Error)?
        do {
            for try await page in repository.assetPages(scope: .allPhotos, pageSize: 1) {
                received.append(page)
            }
        } catch {
            thrown = error
        }
        #expect(thrown is PageError)
        #expect(received.map { $0.map(\.id) } == [["a"]])
        #expect(await repository.assetPagesCallCount == 1)
    }
}
