import CoreGraphics
@testable import DataLayer
import Foundation
import Testing

/// Variance of the Laplacian on code-drawn images (CPU only, so it runs in CI on macOS).
struct SharpnessMeterTests {
    private let meter = SharpnessMeter()

    /// A sharp picture scores higher than the same picture blurred.
    @Test func aSharpPictureBeatsItsBlurredCopy() throws {
        let sharp = try SyntheticImages.pattern(0)
        let blurred = try QualityTestImages.blurred(sharp, factor: 8)
        let sharpScore = try meter.sharpness(of: sharp)
        let blurredScore = try meter.sharpness(of: blurred)
        #expect(sharpScore > blurredScore * 2)
        #expect(blurredScore > 0)
    }

    /// More blur, lower score.
    @Test func moreBlurScoresLower() throws {
        let sharp = try SyntheticImages.pattern(1)
        let slightly = try meter.sharpness(of: QualityTestImages.blurred(sharp, factor: 2))
        let heavily = try meter.sharpness(of: QualityTestImages.blurred(sharp, factor: 10))
        #expect(slightly > heavily)
    }

    /// A flat image has no edges.
    @Test func aFlatImageScoresZero() throws {
        let flat = try QualityTestImages.flat(gray: 0.5)
        #expect(try meter.sharpness(of: flat) < 1e-9)
    }

    /// Orientation doesn't matter: the same pixels turned 90° score the same.
    @Test func rotationDoesNotChangeTheScore() throws {
        let image = try SyntheticImages.pattern(0)
        let rotated = try SyntheticImages.rotatedClockwise(image)
        let upright = try meter.sharpness(of: image)
        let turned = try meter.sharpness(of: rotated)
        #expect(abs(upright - turned) <= upright * 0.01)
    }

    /// The pre-blur damps pixel noise: a noisy flat image scores far below a picture with real edges.
    @Test func noiseScoresBelowRealEdges() throws {
        let noisy = try QualityTestImages.noise(amplitude: 0.03)
        let edges = try SyntheticImages.pattern(0)
        #expect(try meter.sharpness(of: noisy) < meter.sharpness(of: edges))
    }

    /// An image smaller than the kernels can't be measured.
    @Test func aTinyImageThrows() throws {
        let tiny = try QualityTestImages.flat(gray: 0.5, width: 2, height: 2)
        #expect(throws: SharpnessError.imageTooSmall) {
            try meter.sharpness(of: tiny)
        }
    }

    /// The kernels are the ones the ticket names: a Laplacian summing to 0 and a blur summing to 1.
    @Test func kernelsAreTheLaplacianAndANormalizedBlur() {
        #expect(SharpnessMeter.laplacian == [0, 1, 0, 1, -4, 1, 0, 1, 0])
        #expect(abs(SharpnessMeter.preBlur.reduce(0, +) - 1) < 1e-6)
    }
}

/// Code-drawn images for the quality tests.
enum QualityTestImages {
    /// `image` scaled down by `factor` and back up with interpolation: the same picture, blurred.
    static func blurred(_ image: CGImage, factor: Int) throws -> CGImage {
        let small = try draw(width: max(1, image.width / factor), height: max(1, image.height / factor)) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        }
        return try draw(width: image.width, height: image.height) { context in
            context.interpolationQuality = .high
            context.draw(small, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
    }

    /// A single gray level.
    static func flat(gray: CGFloat, width: Int = 320, height: Int = 240) throws -> CGImage {
        try draw(width: width, height: height) { context in
            context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Mid-gray with deterministic per-pixel noise of about `amplitude` (0…1).
    static func noise(amplitude: CGFloat, width: Int = 320, height: Int = 240) throws -> CGImage {
        var generator = SplitMix64(seed: 42)
        return try draw(width: width, height: height) { context in
            for row in 0..<height {
                for column in 0..<width {
                    let offset = (CGFloat(generator.next() % 1_000) / 1_000 - 0.5) * 2 * amplitude
                    let level = 0.5 + offset
                    context.setFillColor(CGColor(red: level, green: level, blue: level, alpha: 1))
                    context.fill(CGRect(x: column, y: row, width: 1, height: 1))
                }
            }
        }
    }

    /// An RGBA bitmap of the given size, drawn by `body`.
    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.featureUnsupported)
        }
        body(context)
        guard let image = context.makeImage() else {
            throw CocoaError(.featureUnsupported)
        }
        return image
    }
}

/// A tiny deterministic random generator, so noise is the same on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
