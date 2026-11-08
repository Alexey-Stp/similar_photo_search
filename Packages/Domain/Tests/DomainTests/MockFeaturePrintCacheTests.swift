import Domain
import DomainTestSupport
import Foundation
import Testing

/// Pins down the cache validity rule that the real SwiftData cache must also follow.
struct MockFeaturePrintCacheTests {
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePrint(revision: Int = 2) -> FeaturePrint {
        FeaturePrint(assetID: "A", revision: revision, vector: [0.1, 0.2], assetModificationDate: modificationDate)
    }

    @Test func returnsEntryWhenIDRevisionAndDateMatch() async {
        let cache = MockFeaturePrintCache(entries: [makePrint()])
        let hit = await cache.cachedFeaturePrint(for: "A", revision: 2, modificationDate: modificationDate)
        #expect(hit == makePrint())
    }

    @Test func missesWhenRevisionDiffers() async {
        let cache = MockFeaturePrintCache(entries: [makePrint(revision: 1)])
        let hit = await cache.cachedFeaturePrint(for: "A", revision: 2, modificationDate: modificationDate)
        #expect(hit == nil)
    }

    @Test func missesWhenAssetWasModified() async {
        let cache = MockFeaturePrintCache(entries: [makePrint()])
        let hit = await cache.cachedFeaturePrint(
            for: "A",
            revision: 2,
            modificationDate: modificationDate.addingTimeInterval(60)
        )
        #expect(hit == nil)
    }

    @Test func storeReplacesPreviousEntry() async {
        let cache = MockFeaturePrintCache(entries: [makePrint(revision: 1)])
        await cache.store(makePrint(revision: 2))
        let hit = await cache.cachedFeaturePrint(for: "A", revision: 2, modificationDate: modificationDate)
        #expect(hit?.revision == 2)
    }
}
