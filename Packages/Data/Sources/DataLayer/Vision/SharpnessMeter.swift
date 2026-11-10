import Accelerate
import CoreGraphics
import Foundation

/// Why sharpness could not be measured.
public enum SharpnessError: Error, Sendable, Hashable {
    /// The image is smaller than the 3×3 kernels.
    case imageTooSmall
    /// vImage could not convert or convolve the image.
    case vImageFailed(Int)
}

/// Measures sharpness as the variance of the Laplacian of the grayscale image. Synchronous and stateless.
///
/// Steps: convert to 8-bit grayscale, then to floats in 0…1, apply a light 3×3 Gaussian pre-blur (so sensor noise in
/// low-light photos is not mistaken for detail), convolve with the Laplacian `[0,1,0, 1,-4,1, 0,1,0]` and return the
/// variance of the result. Higher is sharper. Values are raw: compare them only within one cluster, at the same image
/// size (the 512 px analysis images). Orientation does not matter, so it is ignored.
///
/// Every vImage buffer is freed with `defer`; nothing outlives the call.
public struct SharpnessMeter: Sendable {
    /// The Laplacian kernel.
    static let laplacian: [Float] = [
        0, 1, 0,
        1, -4, 1,
        0, 1, 0
    ]

    /// A 3×3 Gaussian (binomial) kernel, normalized to sum 1.
    static let preBlur: [Float] = [
        1, 2, 1,
        2, 4, 2,
        1, 2, 1
    ].map { $0 / 16 }

    /// Creates a meter.
    public init() {}

    /// The variance of the Laplacian of `image`.
    /// - Throws: `SharpnessError`.
    public func sharpness(of image: CGImage) throws -> Float {
        guard image.width >= 3, image.height >= 3 else {
            throw SharpnessError.imageTooSmall
        }
        guard let grayFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            colorSpace: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        ) else {
            throw SharpnessError.vImageFailed(kvImageInvalidImageFormat)
        }

        var gray = try Self.wrap { try vImage_Buffer(cgImage: image, format: grayFormat) }
        defer { gray.free() }
        let width = Int(gray.width)
        let height = Int(gray.height)

        var planar = try Self.wrap { try vImage_Buffer(width: width, height: height, bitsPerPixel: 32) }
        defer { planar.free() }
        var blurred = try Self.wrap { try vImage_Buffer(width: width, height: height, bitsPerPixel: 32) }
        defer { blurred.free() }
        var edges = try Self.wrap { try vImage_Buffer(width: width, height: height, bitsPerPixel: 32) }
        defer { edges.free() }

        try Self.check(vImageConvert_Planar8toPlanarF(&gray, &planar, 1, 0, vImage_Flags(kvImageNoFlags)))
        try Self.convolve(&planar, into: &blurred, kernel: Self.preBlur)
        try Self.convolve(&blurred, into: &edges, kernel: Self.laplacian)
        return Self.variance(of: edges)
    }

    // MARK: - Private

    /// Convolves a PlanarF buffer with a 3×3 kernel, extending the edges (so the border adds no false edges).
    private static func convolve(_ source: inout vImage_Buffer, into destination: inout vImage_Buffer, kernel: [Float])
        throws {
        let error = kernel.withUnsafeBufferPointer { pointer in
            vImageConvolve_PlanarF(
                &source,
                &destination,
                nil,
                0,
                0,
                pointer.baseAddress,
                3,
                3,
                0,
                vImage_Flags(kvImageEdgeExtend)
            )
        }
        try check(error)
    }

    /// The population variance of a PlanarF buffer, row by row (rows may be padded), accumulated in `Double`.
    private static func variance(of buffer: vImage_Buffer) -> Float {
        let width = Int(buffer.width)
        let height = Int(buffer.height)
        guard let base = buffer.data, width > 0, height > 0 else { return 0 }
        var sum = 0.0
        var sumOfSquares = 0.0
        for row in 0..<height {
            let pointer = base.advanced(by: row * buffer.rowBytes).assumingMemoryBound(to: Float.self)
            let values = UnsafeBufferPointer(start: pointer, count: width)
            sum += Double(vDSP.sum(values))
            sumOfSquares += Double(vDSP.sumOfSquares(values))
        }
        let count = Double(width * height)
        let mean = sum / count
        let variance = max(0, sumOfSquares / count - mean * mean)
        return variance.isFinite ? Float(variance) : 0
    }

    /// Throws for a vImage error code.
    private static func check(_ error: vImage_Error) throws {
        guard error == kvImageNoError else {
            throw SharpnessError.vImageFailed(error)
        }
    }

    /// Runs a throwing vImage initializer, mapping its error to `SharpnessError`.
    private static func wrap(_ body: () throws -> vImage_Buffer) throws -> vImage_Buffer {
        do {
            return try body()
        } catch {
            throw SharpnessError.vImageFailed(kvImageMemoryAllocationError)
        }
    }
}
