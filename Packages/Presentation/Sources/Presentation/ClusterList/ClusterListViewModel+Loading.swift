import CoreGraphics
import Domain
import Foundation

extension ClusterListViewModel {
    // MARK: - Groups changed

    /// The scan added, replaced or removed groups (`ScanViewModel.clusterRevision` changed): looks up the dates and
    /// sizes of members not seen before and, with size sort, re-sorts unless the user is scrolling.
    public func clustersChanged() {
        let members = displayOrder.flatMap { selection.state(for: $0)?.memberIDs ?? [] }
        let newForMetadata = members.filter { !requestedMetadata.contains($0) }
        if !newForMetadata.isEmpty {
            loadMetadata(for: unique(newForMetadata))
        }
        let newForSizes = members.filter { !requestedSizes.contains($0) }
        if !newForSizes.isEmpty {
            loadSizes(for: unique(newForSizes))
        }
        applySizeOrderIfIdle()
    }

    /// Follows library changes while the list is visible: after each one, re-checks which shown photos still
    /// exist, so a photo deleted in the Photos app gets a placeholder at once. (Home's silent rescan then updates the
    /// groups.) Returns when the calling task is cancelled.
    public func observeLibraryChanges() async {
        for await _ in libraryChanges.changes() {
            guard !Task.isCancelled else { return }
            let members = displayOrder.flatMap { selection.state(for: $0)?.memberIDs ?? [] }
            loadMetadata(for: unique(members))
        }
    }

    /// The bytes deleting the group would free: every member except the keeper (except the largest member when
    /// there is no keeper). Stable while the user toggles photos. `nil` while a member's size is still unknown;
    /// unavailable sizes count as 0.
    public func reclaimableBytes(of clusterID: String) -> Int64? {
        guard let state = selection.state(for: clusterID) else { return nil }
        var total: Int64 = 0
        var largest: Int64 = 0
        var keeperSize: Int64?
        for id in state.memberIDs {
            let size: Int64
            if let known = memberSizes[id] {
                size = known
            } else if unavailableSizes.contains(id) {
                size = 0
            } else {
                return nil
            }
            total += size
            largest = max(largest, size)
            if id == state.keeperID {
                keeperSize = size
            }
        }
        return total - (keeperSize ?? largest)
    }

    /// Waits until the lookups started so far have finished. For tests.
    public func waitForLoads() async {
        while !loads.isEmpty {
            let pending = loads
            loads = []
            for task in pending {
                await task.value
            }
        }
        await prefetchTask?.value
    }

    // MARK: - Prefetching

    /// The display scale of the screen; thumbnails are requested at `thumbnailSide × scale` pixels.
    public func displayScaleChanged(_ scale: CGFloat) {
        let side = Self.thumbnailSide * max(1, scale)
        let size = CGSize(width: side, height: side)
        guard size != thumbnailPixelSize else { return }
        thumbnailPixelSize = size
        stopPrefetching()
    }

    /// The pixel size of a thumbnail on this screen.
    public var pixelSize: CGSize { thumbnailPixelSize }

    /// A row appeared: caches the thumbnails of the rows within `prefetchRadius` of it and releases the rest.
    public func rowAppeared(_ clusterID: String) {
        let rows = self.rows
        guard let index = rows.firstIndex(of: clusterID) else { return }
        let window = rows[max(0, index - Self.prefetchRadius)...min(rows.count - 1, index + Self.prefetchRadius)]
        let wanted = Set(window.flatMap { selection.state(for: $0)?.memberIDs ?? [] }).subtracting(missingAssetIDs)
        let start = wanted.subtracting(prefetchedIDs).sorted()
        let stop = prefetchedIDs.subtracting(wanted).sorted()
        guard !start.isEmpty || !stop.isEmpty else { return }
        prefetchedIDs = wanted
        let size = thumbnailPixelSize
        let thumbnails = thumbnails
        let previous = prefetchTask
        prefetchTask = Task {
            await previous?.value
            if !stop.isEmpty {
                await thumbnails.stopPrefetching(stop, pixelSize: size)
            }
            if !start.isEmpty {
                await thumbnails.prefetch(start, pixelSize: size)
            }
        }
    }

    /// The list left the screen: releases every cached thumbnail.
    public func stopPrefetching() {
        prefetchedIDs = []
        let thumbnails = thumbnails
        let previous = prefetchTask
        prefetchTask = Task {
            await previous?.value
            await thumbnails.stopAllPrefetching()
        }
    }

    // MARK: - Private

    /// Looks up dates and existence of these photos.
    private func loadMetadata(for ids: [String]) {
        guard !ids.isEmpty else { return }
        requestedMetadata.formUnion(ids)
        let library = library
        loads.append(Task { [weak self] in
            let found = await library.assets(withIDs: ids)
            self?.recordMetadata(found, requested: ids)
        })
    }

    /// Stores the dates found and marks requested photos that were not found as missing.
    private func recordMetadata(_ found: [PhotoAsset], requested: [String]) {
        var dates = photoDates
        var missing = missingAssetIDs
        let foundIDs = Set(found.map(\.id))
        for asset in found {
            dates[asset.id] = asset.creationDate
        }
        missing.subtract(foundIDs)
        missing.formUnion(Set(requested).subtracting(foundIDs))
        if dates != photoDates {
            photoDates = dates
        }
        if missing != missingAssetIDs {
            missingAssetIDs = missing
        }
    }

    /// Estimates the file sizes of these photos.
    private func loadSizes(for ids: [String]) {
        guard !ids.isEmpty else { return }
        requestedSizes.formUnion(ids)
        let sizes = sizes
        loads.append(Task { [weak self] in
            let found = await sizes.estimatedSizes(of: ids)
            self?.recordSizes(found, requested: ids)
        })
    }

    /// Stores the sizes found (unavailable for the rest) and re-sorts if idle.
    private func recordSizes(_ found: [String: Int64], requested: [String]) {
        for id in requested {
            if let size = found[id], size >= 0 {
                memberSizes[id] = size
            } else {
                unavailableSizes.insert(id)
            }
        }
        applySizeOrderIfIdle()
    }

    /// The IDs without repeats, in their first order.
    private func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
