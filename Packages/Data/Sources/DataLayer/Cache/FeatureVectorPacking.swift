import Foundation

/// Converts feature-print vectors to and from the bytes stored in the analysis cache.
///
/// The bytes are the vector's native `Float`s (little-endian on every Apple device), copied in one block.
public enum FeatureVectorPacking {
    /// The bytes of `vector`.
    public static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// The vector stored in `data`, or `nil` if its size is not a whole number of `Float`s.
    ///
    /// The bytes are copied rather than rebound, so `Data` with any alignment (for example a slice) is safe.
    public static func vector(from data: Data) -> [Float]? {
        let stride = MemoryLayout<Float>.stride
        guard data.count.isMultiple(of: stride) else { return nil }
        let count = data.count / stride
        return [Float](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            let copied = data.copyBytes(to: buffer)
            initializedCount = copied / stride
        }
    }
}
