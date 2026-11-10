import Domain
import DomainTestSupport
import Foundation
import Testing

struct UnionFindClusteringEngineTests {
    private let engine = UnionFindClusteringEngine()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    /// Threshold 1 for revision 2: distances in the tests read as fractions of the threshold.
    private let config = ClusteringConfig(thresholds: [2: 1])

    private func item(
        _ id: String,
        seconds: TimeInterval = 0,
        burst: String? = nil,
        revision: Int = 2,
        _ vector: [Float]
    ) -> VectorItem {
        VectorItem(id: id, date: start.addingTimeInterval(seconds), burstID: burst, revision: revision, vector: vector)
    }

    private func clusters(
        _ items: [VectorItem],
        config: ClusteringConfig? = nil
    ) throws -> [SimilarityCluster] {
        try engine.clusters(in: items, config: config ?? self.config)
    }

    // MARK: - Edge cases

    /// No items, no clusters.
    @Test func emptySessionHasNoClusters() throws {
        #expect(try clusters([]).isEmpty)
    }

    /// A single photo is never a cluster.
    @Test func singleItemHasNoClusters() throws {
        #expect(try clusters([item("A", [0, 0])]).isEmpty)
    }

    /// Photos that are all far apart give only singletons, which are dropped.
    @Test func dissimilarItemsAreDropped() throws {
        let items = [item("A", seconds: 0, [0, 0]), item("B", seconds: 1, [5, 0]), item("C", seconds: 2, [0, 5])]
        #expect(try clusters(items).isEmpty)
    }

    /// All-identical vectors form one cluster, newest photo first, flagged as exact duplicates.
    @Test func identicalVectorsFormOneExactDuplicateCluster() throws {
        let items = (0..<5).map { item("P\($0)", seconds: TimeInterval($0), [0.3, 0.4]) }
        let result = try clusters(items)
        #expect(result.count == 1)
        #expect(result.first?.assetIDs == ["P4", "P3", "P2", "P1", "P0"])
        #expect(result.first?.id == "P4")
        #expect(result.first?.isExactDuplicate == true)
        #expect(result.first?.averageDistance == 0)
    }

    /// A distance exactly at the threshold is an edge.
    @Test func distanceEqualToThresholdIsSimilar() throws {
        let result = try clusters([item("A", seconds: 0, [0]), item("B", seconds: 1, [1])])
        #expect(result.map(\.assetIDs) == [["B", "A"]])
        #expect(result.first?.isExactDuplicate == false)
    }

    /// A distance just over the threshold is not.
    @Test func distanceOverThresholdIsNotSimilar() throws {
        #expect(try clusters([item("A", seconds: 0, [0]), item("B", seconds: 1, [1.01])]).isEmpty)
    }

    // MARK: - maxPairInterval

    /// Two photos exactly `maxPairInterval` apart are compared; one second more and they are not.
    @Test func pairExactlyMaxPairIntervalApartIsCompared() throws {
        let interval = ClusteringConfig.defaultMaxPairInterval
        let atLimit = try clusters([item("A", seconds: 0, [1, 1]), item("B", seconds: interval, [1, 1])])
        #expect(atLimit.map(\.assetIDs) == [["B", "A"]])

        let overLimit = try clusters([item("A", seconds: 0, [1, 1]), item("B", seconds: interval + 1, [1, 1])])
        #expect(overLimit.isEmpty)
    }

    /// Photos too far apart in time can still share a cluster through a photo between them.
    @Test func photosBeyondMaxPairIntervalJoinThroughNeighbours() throws {
        var config = config
        config.maxPairInterval = 10
        let items = [item("A", seconds: 0, [0]), item("B", seconds: 10, [0]), item("C", seconds: 20, [0])]
        #expect(try clusters(items, config: config).map(\.assetIDs) == [["C", "B", "A"]])
    }

    // MARK: - Chaining guard

    /// A–B and B–C are similar but A–C is not: with a guard of 2, the chain is split around the closest pair.
    @Test func chainIsSplitByTheGuard() throws {
        // A–B 0.75, B–C 0.85 (both edges), A–C 1.6 (over 1.15 × threshold).
        let items = [item("A", seconds: 0, [0]), item("B", seconds: 1, [0.75]), item("C", seconds: 2, [1.6])]

        var guarded = config
        guarded.maxChainSize = 2
        #expect(try clusters(items, config: guarded).map(\.assetIDs) == [["B", "A"]])

        // Components no larger than `maxChainSize` are kept whole.
        #expect(try clusters(items, config: config).map(\.assetIDs) == [["C", "B", "A"]])
    }

    /// A long gradient (each photo 0.6 from the next) is cut into groups whose pairs all stay within 1.15 × threshold.
    @Test func longChainIsCutIntoTightGroups() throws {
        let items = (0..<20).map { item(String(format: "P%02d", $0), seconds: TimeInterval($0), [Float($0) * 0.6]) }
        let result = try clusters(items)
        #expect(!result.isEmpty)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.vector[0]) })
        for cluster in result {
            let values = cluster.assetIDs.compactMap { byID[$0] }
            #expect(cluster.assetIDs.count == 2)
            #expect((values.max() ?? 0) - (values.min() ?? 0) <= 1.15)
        }
        let allIDs = result.flatMap(\.assetIDs)
        #expect(Set(allIDs).count == allIDs.count)
    }

    /// A large group of copies is not split by the guard.
    @Test func largeTightGroupSurvivesTheGuard() throws {
        let items = (0..<30).map { item(String(format: "P%02d", $0), seconds: TimeInterval($0), [0.1, 0.1]) }
        let result = try clusters(items)
        #expect(result.count == 1)
        #expect(result.first?.assetIDs.count == 30)
    }

    // MARK: - Bursts

    /// Burst photos are grouped up to `threshold × burstSlack`; other photos are not.
    @Test func burstPhotosGetSlack() throws {
        let sameBurst = [item("A", seconds: 0, burst: "X", [0]), item("B", seconds: 1, burst: "X", [1.05])]
        #expect(try clusters(sameBurst).map(\.assetIDs) == [["B", "A"]])

        let noBurst = [item("A", seconds: 0, [0]), item("B", seconds: 1, [1.05])]
        #expect(try clusters(noBurst).isEmpty)

        let otherBurst = [item("A", seconds: 0, burst: "X", [0]), item("B", seconds: 1, burst: "Y", [1.05])]
        #expect(try clusters(otherBurst).isEmpty)

        let tooFar = [item("A", seconds: 0, burst: "X", [0]), item("B", seconds: 1, burst: "X", [1.15])]
        #expect(try clusters(tooFar).isEmpty)
    }

    // MARK: - Revisions

    /// Identical vectors of two revisions give two clusters, never one mixed cluster.
    @Test func revisionsAreNeverCompared() throws {
        let items = [
            item("A1", seconds: 0, revision: 1, [0.5, 0.5]),
            item("B1", seconds: 1, revision: 1, [0.5, 0.5]),
            item("A2", seconds: 2, revision: 2, [0.5, 0.5]),
            item("B2", seconds: 3, revision: 2, [0.5, 0.5])
        ]
        let result = try clusters(items, config: ClusteringConfig(thresholds: [1: 1, 2: 1]))
        #expect(result.map(\.assetIDs) == [["B2", "A2"], ["B1", "A1"]])
    }

    /// Each revision uses its own threshold.
    @Test func thresholdIsKeyedByRevision() throws {
        let items = [
            item("A1", seconds: 0, revision: 1, [0]),
            item("B1", seconds: 1, revision: 1, [5]),
            item("A2", seconds: 2, revision: 2, [0]),
            item("B2", seconds: 3, revision: 2, [5])
        ]
        let result = try clusters(items, config: ClusteringConfig(thresholds: [1: 10, 2: 1]))
        #expect(result.map(\.assetIDs) == [["B1", "A1"]])
    }

    /// Two or more items of a revision without a threshold throw instead of silently giving no clusters.
    @Test func missingThresholdThrows() {
        let items = [item("A", seconds: 0, revision: 3, [0]), item("B", seconds: 1, revision: 3, [0])]
        #expect(throws: ClusteringError.missingThreshold(revision: 3)) {
            try engine.clusters(in: items, config: config)
        }
    }

    /// A lone item of an unknown revision has nothing to be compared with, so it does not throw.
    @Test func singleItemOfUnknownRevisionDoesNotThrow() throws {
        let items = [item("A", seconds: 0, revision: 3, [0]), item("B", seconds: 1, [0]), item("C", seconds: 2, [0])]
        #expect(try clusters(items).map(\.assetIDs) == [["C", "B"]])
    }

    /// Vectors of different lengths are never compared, even with the same revision.
    @Test func vectorsOfDifferentLengthsAreNotCompared() throws {
        let items = [item("A", seconds: 0, [0]), item("B", seconds: 1, [0, 0]), item("C", seconds: 2, [0, 0])]
        #expect(try clusters(items).map(\.assetIDs) == [["C", "B"]])
    }

    // MARK: - Determinism and order

    /// Running twice, or on shuffled input, gives exactly the same clusters, IDs and order.
    @Test func isDeterministic() throws {
        let items = [
            item("A", seconds: 0, [0, 0]), item("B", seconds: 0, [0, 0.1]), item("C", seconds: 5, [0.2, 0]),
            item("D", seconds: 100, [9, 9]), item("E", seconds: 101, [9, 9.5]),
            item("F", seconds: 200, [-4, 4]), item("G", seconds: 300, [4, -4])
        ]
        let first = try clusters(items)
        #expect(first.count == 2)
        #expect(try clusters(items) == first)
        #expect(try clusters(Array(items.reversed())) == first)
        #expect(try clusters([items[3], items[0], items[6], items[2], items[5], items[1], items[4]]) == first)
    }

    /// Clusters come newest first; members follow library order (newest first, ties by ID).
    @Test func ordersClustersAndMembersNewestFirst() throws {
        let items = [
            item("old-b", seconds: 0, [0]), item("old-a", seconds: 0, [0]),
            item("new-b", seconds: 500, [50]), item("new-a", seconds: 500, [50]), item("new-c", seconds: 400, [50])
        ]
        let result = try clusters(items)
        #expect(result.map(\.assetIDs) == [["new-a", "new-b", "new-c"], ["old-a", "old-b"]])
        #expect(result.map(\.id) == ["new-a", "old-a"])
    }

    /// A repeated ID is used once.
    @Test func duplicateIDsAreIgnored() throws {
        let items = [item("A", seconds: 0, [0]), item("A", seconds: 0, [0]), item("B", seconds: 1, [0])]
        #expect(try clusters(items).map(\.assetIDs) == [["B", "A"]])
    }

    // MARK: - averageDistance

    /// `averageDistance` is the mean distance over all pairs of the cluster.
    @Test func averageDistanceIsMeanOverAllPairs() throws {
        let pair = try clusters([item("A", seconds: 0, [0]), item("B", seconds: 1, [0.5])])
        #expect(abs((pair.first?.averageDistance ?? -1) - 0.5) < 1e-6)

        // Pairs: 0.4, 0.8, 0.4, mean 0.5333.
        let tripleItems = [item("A", seconds: 0, [0]), item("B", seconds: 1, [0.4]), item("C", seconds: 2, [0.8])]
        let triple = try clusters(tripleItems)
        #expect(abs((triple.first?.averageDistance ?? -1) - 1.6 / 3) < 1e-5)
    }
}

struct ClusteringSupportTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func asset(id: String, date: Date?) -> PhotoAsset {
        PhotoAsset(
            id: id,
            creationDate: date,
            pixelWidth: 10,
            pixelHeight: 10,
            isFavorite: false,
            mediaSubtypes: [],
            burstIdentifier: "burst"
        )
    }

    /// A `VectorItem` takes date and burst from the photo, revision and vector from its print.
    @Test func vectorItemIsBuiltFromAssetAndPrint() {
        let print = FeaturePrint(assetID: "A", revision: 2, vector: [1, 2], assetModificationDate: nil)
        let item = VectorItem(asset: asset(id: "A", date: date), featurePrint: print)
        #expect(item == VectorItem(id: "A", date: date, burstID: "burst", revision: 2, vector: [1, 2]))
    }

    /// No item without a date or for another photo's print.
    @Test func vectorItemNeedsDateAndMatchingPrint() {
        let print = FeaturePrint(assetID: "A", revision: 2, vector: [1, 2], assetModificationDate: nil)
        #expect(VectorItem(asset: asset(id: "A", date: nil), featurePrint: print) == nil)
        #expect(VectorItem(asset: asset(id: "B", date: date), featurePrint: print) == nil)
    }

    /// The defaults match the ticket: 60 min pairs, guard at 12, burst × 1.1, linkage × 1.15.
    @Test func configDefaults() {
        let config = ClusteringConfig(thresholds: [2: 0.5])
        #expect(config.maxPairInterval == 3_600)
        #expect(config.maxChainSize == 12)
        #expect(config.burstSlack == 1.1)
        #expect(config.chainLinkageSlack == 1.15)
        #expect(config.threshold(forRevision: 2) == 0.5)
        #expect(config.threshold(forRevision: 1) == nil)
    }

    /// The mock records its calls and returns or throws what it was given.
    @Test func mockRecordsCalls() throws {
        let cluster = SimilarityCluster(assetIDs: ["A", "B"])
        let mock = MockClusteringEngine(result: [cluster])
        let items = [VectorItem(id: "A", date: date, revision: 2, vector: [0])]
        let config = ClusteringConfig(thresholds: [2: 1])
        #expect(try mock.clusters(in: items, config: config) == [cluster])
        #expect(mock.calls == [MockClusteringEngine.Call(session: items, config: config)])

        let failing = MockClusteringEngine(error: .missingThreshold(revision: 2))
        #expect(throws: ClusteringError.missingThreshold(revision: 2)) {
            try failing.clusters(in: items, config: config)
        }
    }
}
