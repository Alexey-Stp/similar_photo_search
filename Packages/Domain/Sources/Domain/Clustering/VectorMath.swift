#if canImport(Accelerate)
import Accelerate
#endif
import Foundation

/// Distances between feature-print vectors.
///
/// Lives in `Domain/Clustering`, the only Domain folder allowed to import Accelerate, so the clustering engine can use
/// it. Without Accelerate (Linux, Windows) a plain loop gives the same result, so Domain tests run everywhere.
public enum VectorMath {
    /// The Euclidean distance between two vectors of the same length.
    ///
    /// For Vision feature prints this matches `VNFeaturePrintObservation.computeDistance(_:to:)` within 1e-4. Only
    /// compare vectors of the same revision (`FeaturePrint.isComparable(with:)`).
    public static func euclideanDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        euclideanDistanceSquared(lhs, rhs).squareRoot()
    }

    /// The squared Euclidean distance between two vectors of the same length. Cheaper than `euclideanDistance` when
    /// only comparing against a threshold (compare with `threshold * threshold`).
    public static func euclideanDistanceSquared(_ lhs: [Float], _ rhs: [Float]) -> Float {
        precondition(lhs.count == rhs.count, "Vectors of different lengths: \(lhs.count) and \(rhs.count)")
        #if canImport(Accelerate)
        return vDSP.distanceSquared(lhs, rhs)
        #else
        var sum: Float = 0
        for index in lhs.indices {
            let difference = lhs[index] - rhs[index]
            sum += difference * difference
        }
        return sum
        #endif
    }
}
