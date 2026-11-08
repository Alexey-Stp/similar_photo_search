import Foundation

extension PhotoAsset {
    /// The order in which `PhotoLibraryRepository` delivers assets: `creationDate` descending
    /// (newest first), ties broken by `id` ascending, and assets without a `creationDate` last (by `id`).
    ///
    /// Session splitting and live results depend on this order, so it is a hard contract.
    /// Use it as `assets.sorted(by: PhotoAsset.libraryOrder)`.
    public static func libraryOrder(_ lhs: PhotoAsset, _ rhs: PhotoAsset) -> Bool {
        switch (lhs.creationDate, rhs.creationDate) {
        case let (lhsDate?, rhsDate?):
            return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.id < rhs.id
        }
    }
}
