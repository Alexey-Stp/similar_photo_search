import Foundation

/// Clusters one shooting session: time-limited pairs, distance threshold, Union-Find, then a chaining guard.
///
/// 1. Items are deduplicated by ID, sorted by date then ID, and partitioned by revision and vector length.
/// 2. Within a partition, a pair is compared only if the photos are at most `maxPairInterval` apart (a two-pointer
///    sweep over the sorted dates). It becomes an edge if the squared distance is at most the squared threshold, or
///    `threshold × burstSlack` for two photos of the same burst. There is no square root in this loop.
/// 3. Edges are joined with Union-Find (path compression, union by rank).
/// 4. Components larger than `maxChainSize` are re-clustered with complete linkage: groups are merged, closest first,
///    only while every pair stays within `chainLinkageSlack` × its threshold. This splits A~B~C chains where A and C
///    differ. Every pair counts here, including pairs further apart in time than `maxPairInterval`.
/// 5. Singletons are dropped; each cluster gets `averageDistance` and `isExactDuplicate`.
///
/// Pure and deterministic: no state, no Apple frameworks except Accelerate (through `VectorMath`). Cost is
/// O(s · w) distance computations for a session of `s` photos with at most `w` photos per `maxPairInterval`, plus
/// O(k³) comparisons (O(k²) distances) for each guarded component of `k` photos whose pairs are not all within
/// the slack.
public struct UnionFindClusteringEngine: ClusteringEngine {
    /// Creates the engine.
    public init() {}

    public func clusters(
        in session: [VectorItem],
        config: ClusteringConfig
    ) throws(ClusteringError) -> [SimilarityCluster] {
        var found: [FoundCluster] = []
        for partition in Self.partitions(of: Self.uniqueItemsInDateOrder(session)) where partition.items.count >= 2 {
            guard let threshold = config.threshold(forRevision: partition.revision) else {
                throw .missingThreshold(revision: partition.revision)
            }
            let clusterer = PartitionClusterer(items: partition.items, threshold: max(0, threshold), config: config)
            found += clusterer.clusters()
        }
        return found
            .sorted { lhs, rhs in
                lhs.newestDate == rhs.newestDate ? lhs.cluster.id < rhs.cluster.id : lhs.newestDate > rhs.newestDate
            }
            .map(\.cluster)
    }

    /// Items sorted by date, then ID (revision and length break the rest), keeping only the first item of each ID.
    private static func uniqueItemsInDateOrder(_ items: [VectorItem]) -> [VectorItem] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
            return lhs.vector.count < rhs.vector.count
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    /// Items grouped by revision and vector length, in that key order; each group stays in date order.
    private static func partitions(of items: [VectorItem]) -> [Partition] {
        var byKey: [PartitionKey: [VectorItem]] = [:]
        for item in items {
            byKey[PartitionKey(revision: item.revision, length: item.vector.count), default: []].append(item)
        }
        return byKey
            .sorted { lhs, rhs in
                lhs.key.revision == rhs.key.revision
                    ? lhs.key.length < rhs.key.length
                    : lhs.key.revision < rhs.key.revision
            }
            .map { Partition(revision: $0.key.revision, items: $0.value) }
    }
}

private struct PartitionKey: Hashable {
    let revision: Int
    let length: Int
}

private struct Partition {
    let revision: Int
    let items: [VectorItem]
}

private struct FoundCluster {
    let cluster: SimilarityCluster
    let newestDate: Date
}

/// Clusters the items of one partition (one revision and length), sorted by date then ID.
private struct PartitionClusterer {
    let items: [VectorItem]
    let threshold: Float
    let config: ClusteringConfig

    func clusters() -> [FoundCluster] {
        let vectors = items.map(\.vector)
        let times = items.map(\.date.timeIntervalSinceReferenceDate)
        let maxInterval = max(0, config.maxPairInterval)
        var unionFind = UnionFind(count: items.count)

        for first in items.indices {
            var second = first + 1
            while second < items.count, times[second] - times[first] <= maxInterval {
                let limit = pairLimit(first, second)
                if VectorMath.euclideanDistanceSquared(vectors[first], vectors[second]) <= limit * limit {
                    unionFind.union(first, second)
                }
                second += 1
            }
        }

        let maxChainSize = max(2, config.maxChainSize)
        var result: [FoundCluster] = []
        for component in unionFind.components() where component.count >= 2 {
            let groups = component.count > maxChainSize ? completeLinkage(component) : [component]
            for group in groups where group.count >= 2 {
                result.append(makeCluster(group))
            }
        }
        return result
    }

    /// The distance threshold for a pair: `threshold`, widened by `burstSlack` for two photos of the same burst.
    private func pairLimit(_ first: Int, _ second: Int) -> Float {
        if let burst = items[first].burstID, burst == items[second].burstID {
            return threshold * max(0, config.burstSlack)
        }
        return threshold
    }

    /// Squared distance divided by the squared pair limit: at most 1 means "within the threshold". Never NaN.
    private func normalizedDistanceSquared(_ first: Int, _ second: Int) -> Float {
        let distanceSquared = VectorMath.euclideanDistanceSquared(items[first].vector, items[second].vector)
        guard !distanceSquared.isNaN else { return .infinity }
        let limit = pairLimit(first, second)
        guard limit > 0 else { return distanceSquared == 0 ? 0 : .infinity }
        return distanceSquared / (limit * limit)
    }

    /// Splits a component (item indices, ascending) into groups whose pairs are all within the linkage slack.
    ///
    /// Agglomerative complete linkage: start from singletons, repeatedly merge the two groups with the smallest
    /// largest-pair distance (first pair in index order on ties) while that distance is within the slack.
    private func completeLinkage(_ members: [Int]) -> [[Int]] {
        let count = members.count
        let slack = max(0, config.chainLinkageSlack)
        let slackSquared = slack * slack
        var linkage = linkageMatrix(members)
        // Common case for a large tight group (for example many copies of one image): nothing to split.
        if linkage.allSatisfy({ $0 <= slackSquared }) { return [members] }

        var groups: [[Int]] = (0..<count).map { [$0] }
        var active = Array(0..<count)
        while active.count > 1 {
            var best = Float.infinity
            var bestPair: (Int, Int)?
            for left in 0..<active.count {
                let rowOffset = active[left] * count
                for right in (left + 1)..<active.count where linkage[rowOffset + active[right]] < best {
                    best = linkage[rowOffset + active[right]]
                    bestPair = (left, right)
                }
            }
            guard let pair = bestPair, best <= slackSquared else { break }

            let kept = active[pair.0]
            let merged = active[pair.1]
            for other in active where other != kept && other != merged {
                let value = max(linkage[kept * count + other], linkage[merged * count + other])
                linkage[kept * count + other] = value
                linkage[other * count + kept] = value
            }
            groups[kept] += groups[merged]
            active.remove(at: pair.1)
        }
        return active.map { groups[$0].map { members[$0] }.sorted() }
    }

    /// Row-major `members.count²` matrix of `normalizedDistanceSquared` between members; 0 on the diagonal.
    private func linkageMatrix(_ members: [Int]) -> [Float] {
        let count = members.count
        var matrix = [Float](repeating: 0, count: count * count)
        for row in 0..<count {
            for column in (row + 1)..<count {
                let value = normalizedDistanceSquared(members[row], members[column])
                matrix[row * count + column] = value
                matrix[column * count + row] = value
            }
        }
        return matrix
    }

    /// A cluster of the given item indices: members in library order, average and exact-duplicate flag over all pairs.
    private func makeCluster(_ group: [Int]) -> FoundCluster {
        var distanceSum: Double = 0
        var pairCount = 0
        var isExactDuplicate = true
        for first in group.indices {
            for second in (first + 1)..<group.count {
                let distance = VectorMath.euclideanDistance(items[group[first]].vector, items[group[second]].vector)
                distanceSum += Double(distance)
                pairCount += 1
                if !(distance <= config.exactDuplicateDistance) { isExactDuplicate = false }
            }
        }
        let unordered: [VectorItem] = group.map { (index: Int) -> VectorItem in items[index] }
        let members: [VectorItem] = unordered.sorted { (lhs: VectorItem, rhs: VectorItem) -> Bool in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
        let assetIDs: [String] = members.map { (member: VectorItem) -> String in member.id }
        let cluster = SimilarityCluster(
            assetIDs: assetIDs,
            averageDistance: pairCount > 0 ? Float(distanceSum / Double(pairCount)) : 0,
            isExactDuplicate: isExactDuplicate
        )
        return FoundCluster(cluster: cluster, newestDate: members[0].date)
    }
}

/// Disjoint sets over `0..<count` with path compression and union by rank.
struct UnionFind {
    private var parent: [Int]
    private var rank: [UInt8]

    init(count: Int) {
        parent = Array(0..<count)
        rank = [UInt8](repeating: 0, count: count)
    }

    /// The representative of `element`'s set; compresses the path to it.
    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var current = element
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    /// Joins the sets of `first` and `second`.
    mutating func union(_ first: Int, _ second: Int) {
        let firstRoot = find(first)
        let secondRoot = find(second)
        guard firstRoot != secondRoot else { return }
        if rank[firstRoot] < rank[secondRoot] {
            parent[firstRoot] = secondRoot
        } else if rank[firstRoot] > rank[secondRoot] {
            parent[secondRoot] = firstRoot
        } else {
            parent[secondRoot] = firstRoot
            rank[firstRoot] += 1
        }
    }

    /// Every set, members ascending, ordered by smallest member.
    mutating func components() -> [[Int]] {
        var indexByRoot: [Int: Int] = [:]
        var result: [[Int]] = []
        for element in parent.indices {
            let root = find(element)
            if let index = indexByRoot[root] {
                result[index].append(element)
            } else {
                indexByRoot[root] = result.count
                result.append([element])
            }
        }
        return result
    }
}
