import Domain
import Foundation
import Photos

/// Builds the `PHFetchOptions` for a `ScanScope`.
enum PhotoKitFetchOptions {
    /// Images only, sorted by `creationDate` descending, hidden assets excluded, with the scope's
    /// screenshot, date-range and burst settings applied.
    ///
    /// PhotoKit cannot sort by `localIdentifier`, and where it puts photos without a date is not
    /// documented; `OrderedAssetPager` restores the full `PhotoAsset.libraryOrder` contract.
    static func make(scope: ScanScope) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = predicate(for: scope)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = scope.includeBursts
        return options
    }

    /// The filter predicate for `scope`.
    static func predicate(for scope: ScanScope) -> NSPredicate {
        var predicates = [
            NSPredicate(format: "mediaType == %@", NSNumber(value: PHAssetMediaType.image.rawValue))
        ]
        if scope.excludeScreenshots {
            let screenshot = NSNumber(value: PHAssetMediaSubtype.photoScreenshot.rawValue)
            predicates.append(NSPredicate(format: "(mediaSubtypes & %@) == 0", screenshot))
        }
        if let range = scope.dateRange {
            predicates.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                range.lowerBound as NSDate,
                range.upperBound as NSDate
            ))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
