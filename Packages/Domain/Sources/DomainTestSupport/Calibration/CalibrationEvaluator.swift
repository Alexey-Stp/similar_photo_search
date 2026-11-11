import Domain
import Foundation

/// Measures clustering on a `CalibrationFixture` the way a scan runs it (SPS-28).
///
/// The photos are cut into sessions with the real `SessionSegmenter`, each session is clustered with the real
/// `UnionFindClusteringEngine`, and the result is scored pairwise against the group labels: a labelled pair whose
/// photos land in different sessions counts as missed, so the session gap shows up in recall.
public struct CalibrationEvaluator: Sendable {
    /// The labelled set.
    public let fixture: CalibrationFixture
    private let engine = UnionFindClusteringEngine()
    private let labelledPairs: Set<PhotoPair>

    /// Creates an evaluator for `fixture`.
    public init(fixture: CalibrationFixture) {
        self.fixture = fixture
        labelledPairs = Self.labelledPairs(in: fixture.photos)
    }

    /// The fixture's photos cut into sessions with `sessionConfig`, newest session first.
    public func sessions(_ sessionConfig: SessionConfig) async throws -> [[CalibrationPhoto]] {
        let photoByID = Dictionary(fixture.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let assets = fixture.photos.map(\.photoAsset).sorted(by: PhotoAsset.libraryOrder)
        let pages = AsyncThrowingStream<[PhotoAsset], Error> { continuation in
            continuation.yield(assets)
            continuation.finish()
        }
        var result: [[CalibrationPhoto]] = []
        for try await event in SessionSegmenter().sessions(from: pages, config: sessionConfig) {
            if case .session(let session) = event {
                result.append(session.assets.compactMap { photoByID[$0.id] })
            }
        }
        return result
    }

    /// Pairwise precision and recall of clustering with `config` on sessions cut with `sessionConfig`.
    public func score(config: ClusteringConfig, sessionConfig: SessionConfig) async throws -> PairwiseScore {
        try score(config: config, sessions: await sessions(sessionConfig))
    }

    /// Pairwise precision and recall of clustering already-cut `sessions` with `config`.
    public func score(config: ClusteringConfig, sessions: [[CalibrationPhoto]]) throws -> PairwiseScore {
        var predicted = Set<PhotoPair>()
        for session in sessions where session.count >= 2 {
            for cluster in try engine.clusters(in: session.map(\.vectorItem), config: config) {
                predicted.formUnion(PhotoPair.allPairs(of: cluster.assetIDs))
            }
        }
        let truePositives = predicted.intersection(labelledPairs).count
        return PairwiseScore(
            truePositives: truePositives,
            falsePositives: predicted.count - truePositives,
            falseNegatives: labelledPairs.count - truePositives
        )
    }

    /// The precision/recall curve for `revision` over `thresholds`, other parameters from `base`.
    public func curve(
        thresholds: [Float],
        revision: Int,
        base: ClusteringConfig = ClusteringConfig(thresholds: [:]),
        sessionConfig: SessionConfig = .default
    ) async throws -> [CurvePoint] {
        let sessions = try await sessions(sessionConfig)
        return try thresholds.sorted().map { threshold in
            var config = base
            config.thresholds[revision] = threshold
            return CurvePoint(threshold: threshold, score: try score(config: config, sessions: sessions))
        }
    }

    /// How many labelled pairs each session gap separates: those pairs can never be found.
    public func sessionGapSplits(gaps: [TimeInterval]) async throws -> [SessionGapSplit] {
        var result: [SessionGapSplit] = []
        for gap in gaps {
            var sessionByPhoto: [String: Int] = [:]
            for (index, session) in try await sessions(SessionConfig(sessionGap: gap)).enumerated() {
                for photo in session { sessionByPhoto[photo.id] = index }
            }
            let split = labelledPairs.filter { sessionByPhoto[$0.first] != sessionByPhoto[$0.second] }.count
            result.append(SessionGapSplit(gap: gap, labelledPairs: labelledPairs.count, splitPairs: split))
        }
        return result
    }

    /// The point with the best recall among those with at least `minimumPrecision`; the smallest threshold on ties.
    public static func bestPoint(on curve: [CurvePoint], minimumPrecision: Double) -> CurvePoint? {
        curve
            .filter { $0.score.precision >= minimumPrecision }
            .min { lhs, rhs in
                guard lhs.score.recall == rhs.score.recall else { return lhs.score.recall > rhs.score.recall }
                return lhs.threshold < rhs.threshold
            }
    }

    /// Every pair of photos that share a group label.
    private static func labelledPairs(in photos: [CalibrationPhoto]) -> Set<PhotoPair> {
        Dictionary(grouping: photos, by: \.group).values.reduce(into: Set<PhotoPair>()) { pairs, members in
            pairs.formUnion(PhotoPair.allPairs(of: members.map(\.id)))
        }
    }
}

/// Pairwise clustering quality: a pair is predicted "same" if both photos are in one cluster.
public struct PairwiseScore: Sendable, Hashable {
    /// Pairs in one cluster that share a label.
    public let truePositives: Int
    /// Pairs in one cluster with different labels.
    public let falsePositives: Int
    /// Pairs with one label that are not in one cluster (also when they are in different sessions).
    public let falseNegatives: Int

    /// Creates a score.
    public init(truePositives: Int, falsePositives: Int, falseNegatives: Int) {
        self.truePositives = truePositives
        self.falsePositives = falsePositives
        self.falseNegatives = falseNegatives
    }

    /// Share of predicted pairs that are right; 1 when nothing is predicted.
    public var precision: Double {
        let predicted = truePositives + falsePositives
        return predicted == 0 ? 1 : Double(truePositives) / Double(predicted)
    }

    /// Share of labelled pairs that are found; 1 when nothing is labelled.
    public var recall: Double {
        let labelled = truePositives + falseNegatives
        return labelled == 0 ? 1 : Double(truePositives) / Double(labelled)
    }
}

/// One point of the precision/recall curve.
public struct CurvePoint: Sendable, Hashable {
    /// The distance threshold.
    public let threshold: Float
    /// The score at that threshold.
    public let score: PairwiseScore

    /// Creates a point.
    public init(threshold: Float, score: PairwiseScore) {
        self.threshold = threshold
        self.score = score
    }
}

/// How many labelled pairs a session gap puts into different sessions.
public struct SessionGapSplit: Sendable, Hashable {
    /// The session gap in seconds.
    public let gap: TimeInterval
    /// All labelled pairs.
    public let labelledPairs: Int
    /// Labelled pairs whose photos are in different sessions.
    public let splitPairs: Int

    /// The best recall clustering can reach with this gap.
    public var recallCeiling: Double {
        labelledPairs == 0 ? 1 : Double(labelledPairs - splitPairs) / Double(labelledPairs)
    }
}

/// An unordered pair of photo IDs.
struct PhotoPair: Hashable {
    /// The smaller ID.
    let first: String
    /// The larger ID.
    let second: String

    /// The pair of `lhs` and `rhs`, in either order.
    init(_ lhs: String, _ rhs: String) {
        first = min(lhs, rhs)
        second = max(lhs, rhs)
    }

    /// Every pair of distinct positions in `ids`: n·(n−1)/2 pairs.
    static func allPairs(of ids: [String]) -> [PhotoPair] {
        var pairs: [PhotoPair] = []
        for (index, lhs) in ids.enumerated() {
            for rhs in ids[(index + 1)...] { pairs.append(PhotoPair(lhs, rhs)) }
        }
        return pairs
    }
}
