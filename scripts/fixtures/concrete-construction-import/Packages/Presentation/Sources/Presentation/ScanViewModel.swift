// Fixture for check-concrete-construction.sh (SPS-30): Presentation imports DataLayer but uses only the protocol.
import DataLayer
import Domain

struct ScanViewModel {
    let repository: any PhotoLibraryRepository
}
