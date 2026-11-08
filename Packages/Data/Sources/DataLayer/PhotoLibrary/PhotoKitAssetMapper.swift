import Domain
import Foundation
import Photos

/// Converts PhotoKit assets to `Sendable` domain values.
enum PhotoKitAssetMapper {
    /// The domain description of `asset`. Reads metadata only; no pixel data is loaded.
    static func asset(from asset: PHAsset) -> PhotoAsset {
        PhotoAsset(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            mediaSubtypes: subtypes(from: asset.mediaSubtypes),
            burstIdentifier: asset.burstIdentifier
        )
    }

    /// The domain subtypes present in a PhotoKit subtype mask. Flags the domain does not model are ignored.
    static func subtypes(from mask: PHAssetMediaSubtype) -> Set<PhotoSubtype> {
        var result: Set<PhotoSubtype> = []
        if mask.contains(.photoScreenshot) {
            result.insert(.screenshot)
        }
        if mask.contains(.photoHDR) {
            result.insert(.hdr)
        }
        if mask.contains(.photoPanorama) {
            result.insert(.panorama)
        }
        if mask.contains(.photoLive) {
            result.insert(.livePhoto)
        }
        if mask.contains(.photoDepthEffect) {
            result.insert(.depthEffect)
        }
        return result
    }
}
