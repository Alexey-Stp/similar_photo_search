import Foundation

/// Ranks the members of one cluster by weighted quality. Pure and deterministic.
///
/// 1. A signal is **used** only if every member has a finite value for it (no faces in one photo, or no aesthetics
///    before iOS 18, drops that signal for the whole cluster), and only if its weight is above 0.
/// 2. Each used signal is min-max normalized **within the cluster** to 0…1. A signal with the same value for every
///    member normalizes to 1 for all of them: it can't tell them apart, so it moves no one.
/// 3. Score = Σ weight·normalized / Σ weight over the used signals, so the remaining weights again sum to 1
///    and every score is in 0…1. With no used signal, every score is 0.
/// 4. Best first; equal scores by asset ID. Favorites are marked `isProtected` whatever their score.
public struct QualityRanker: Sendable {
    /// Creates a ranker.
    public init() {}

    /// Ranks the members of one cluster, best first.
    /// - Parameters:
    ///   - signals: The signals of every member to rank, keyed by asset ID. Members without signals (skipped or failed
    ///     photos) are not ranked; the caller must not pre-select them for deletion.
    ///   - weights: How much each signal counts.
    public func rank(_ signals: [String: QualitySignals], weights: QualityWeights = .standard) -> [RankedMember] {
        let sorted = signals.sorted { $0.key < $1.key }
        guard !sorted.isEmpty else { return [] }
        let ids = sorted.map(\.key)
        let members = sorted.map(\.value)

        var weighted = [Double](repeating: 0, count: ids.count)
        var reasons = [[QualityReason]](repeating: [], count: ids.count)
        var totalWeight = 0.0

        for signal in Signal.allCases {
            let weight = max(0, signal.weight(in: weights))
            guard weight > 0 else { continue }
            let values = members.map(signal.value)
            guard let present = Self.allFinite(values),
                  let low = present.min(),
                  let high = present.max() else { continue }
            totalWeight += weight

            let range = high - low
            let discriminates = range > 1e-9 * max(1, abs(high))
            for index in present.indices {
                let normalized = discriminates ? (present[index] - low) / range : 1
                weighted[index] += weight * normalized
                if discriminates, present[index] == high {
                    reasons[index].append(signal.reason)
                }
            }
        }

        let ranked = ids.indices.map { index in
            let score = totalWeight > 0 ? min(1, max(0, weighted[index] / totalWeight)) : 0
            let isProtected = members[index].isFavorite
            return RankedMember(
                assetID: ids[index],
                score: score,
                isProtected: isProtected,
                reasons: (isProtected ? [.favorite] : []) + reasons[index]
            )
        }
        return ranked.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.assetID < rhs.assetID
        }
    }

    /// The values as non-optional doubles, or `nil` if any is missing or not finite.
    private static func allFinite(_ values: [Double?]) -> [Double]? {
        var result: [Double] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard let value, value.isFinite else { return nil }
            result.append(value)
        }
        return result
    }

    /// The weighted signals, in the order their reasons are listed.
    private enum Signal: CaseIterable {
        case sharpness
        case faceQuality
        case resolution
        case aesthetics

        func weight(in weights: QualityWeights) -> Double {
            switch self {
            case .sharpness: weights.sharpness
            case .faceQuality: weights.faceQuality
            case .resolution: weights.resolution
            case .aesthetics: weights.aesthetics
            }
        }

        func value(_ signals: QualitySignals) -> Double? {
            switch self {
            case .sharpness: Double(signals.sharpness)
            case .faceQuality: signals.faceQuality.map(Double.init)
            case .resolution: Double(signals.pixelCount)
            case .aesthetics: signals.aesthetics.map(Double.init)
            }
        }

        var reason: QualityReason {
            switch self {
            case .sharpness: .sharpest
            case .faceQuality: .bestFaces
            case .resolution: .highestResolution
            case .aesthetics: .bestAesthetics
            }
        }
    }
}
