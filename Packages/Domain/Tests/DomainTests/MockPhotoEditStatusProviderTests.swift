import DomainTestSupport
import Testing

struct MockPhotoEditStatusProviderTests {
    @Test func returnsOnlyRequestedEditedPhotosAndRecordsRequests() async {
        let provider = MockPhotoEditStatusProvider(edited: ["A", "C"])
        let edited = await provider.editedAssetIDs(among: ["A", "B"])
        #expect(edited == ["A"])
        #expect(await provider.requests == [["A", "B"]])
    }
}
