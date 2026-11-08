import Domain
import Foundation
import Testing

struct PhotoLibraryOrderingTests {
    private func asset(_ id: String, _ seconds: TimeInterval?) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: seconds.map { Date(timeIntervalSince1970: $0) },
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaSubtypes: []
        )
    }

    @Test func newestComesFirst() {
        let sorted = [asset("old", 100), asset("new", 300), asset("mid", 200)].sorted(by: PhotoAsset.libraryOrder)
        #expect(sorted.map(\.id) == ["new", "mid", "old"])
    }

    @Test func equalTimestampsAreOrderedByID() {
        let sorted = [asset("C", 100), asset("A", 100), asset("B", 100)].sorted(by: PhotoAsset.libraryOrder)
        #expect(sorted.map(\.id) == ["A", "B", "C"])
    }

    @Test func assetsWithoutDateComeLastOrderedByID() {
        let input = [asset("Z", nil), asset("dated", 1), asset("Y", nil)]
        let sorted = input.sorted(by: PhotoAsset.libraryOrder)
        #expect(sorted.map(\.id) == ["dated", "Y", "Z"])
    }

    @Test func orderIsStrict() {
        let same = asset("A", 100)
        #expect(!PhotoAsset.libraryOrder(same, same))
        #expect(!PhotoAsset.libraryOrder(asset("A", nil), asset("A", nil)))
    }
}
