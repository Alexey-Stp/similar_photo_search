import Domain
import Foundation
import Photos

/// A date-sorted list of assets that can be read in index ranges without loading all of it.
///
/// It is the seam between the paging logic and PhotoKit: tests use in-memory sources.
/// Sources are not `Sendable`; create and use them inside one isolation domain.
protocol AssetSource {
    /// Number of assets in the source.
    var count: Int { get }
    /// The assets at `range`, in source order (`creationDate` descending).
    func assets(in range: Range<Int>) -> [PhotoAsset]
}

/// An `AssetSource` backed by a lazy `PHFetchResult`. Only the requested range is materialized.
struct PHFetchResultSource: AssetSource {
    /// The fetch result to read from. It must already be sorted by `creationDate` descending.
    let result: PHFetchResult<PHAsset>

    /// Number of assets in the fetch result. Reading it loads no assets.
    var count: Int {
        result.count
    }

    /// Materializes only `range` and maps it to domain values inside an autorelease pool.
    func assets(in range: Range<Int>) -> [PhotoAsset] {
        autoreleasepool {
            result.objects(at: IndexSet(integersIn: range)).map(PhotoKitAssetMapper.asset(from:))
        }
    }
}
