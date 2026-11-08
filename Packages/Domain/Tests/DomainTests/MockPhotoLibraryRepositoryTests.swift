import Domain
import DomainTestSupport
import Foundation
import Testing

struct MockPhotoLibraryRepositoryTests {
    private struct PageError: Error {}

    private func asset(_ id: String, _ seconds: TimeInterval?, screenshot: Bool = false) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: seconds.map { Date(timeIntervalSince1970: $0) },
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: screenshot ? [.screenshot] : []
        )
    }

    private func collect(_ stream: AsyncThrowingStream<[PhotoAsset], Error>) async throws -> [[PhotoAsset]] {
        var pages: [[PhotoAsset]] = []
        for try await page in stream {
            pages.append(page)
        }
        return pages
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
