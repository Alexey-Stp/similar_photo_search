import DataLayer
import Domain
import Photos
import Testing

struct PhotoKitPermissionServiceTests {
    @Test(arguments: [
        (PHAuthorizationStatus.notDetermined, PhotoLibraryAuthorization.notDetermined),
        (.authorized, .authorized),
        (.limited, .limited),
        (.denied, .denied),
        (.restricted, .restricted)
    ])
    func mapsEveryKnownStatus(status: PHAuthorizationStatus, expected: PhotoLibraryAuthorization) {
        #expect(PhotoKitPermissionService.map(status) == expected)
    }

    @Test func mapsUnknownFutureStatusToDenied() throws {
        let unknown = try #require(PHAuthorizationStatus(rawValue: 99))
        #expect(PhotoKitPermissionService.map(unknown) == .denied)
    }
}
