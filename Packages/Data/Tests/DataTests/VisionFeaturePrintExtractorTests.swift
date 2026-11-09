import CoreGraphics
@testable import DataLayer
import Domain
import Foundation
import ImageIO
import Testing
import Vision

/// Runs real Vision on small synthetic images. Absolute distances differ between the Simulator, a Mac and a device;
/// these tests only compare Vision with itself, so they hold everywhere. Real photos: `VisionFeaturePrintDeviceTests`.
struct VisionFeaturePrintExtractorTests {
    private let extractor = VisionFeaturePrintExtractor()

    // MARK: - Request configuration

    @Test func usesRevision2AndAFixedScaleFill() {
        #expect(extractor.revision == VNGenerateImageFeaturePrintRequestRevision2)
        let request = extractor.makeRequest()
        #expect(request.revision == VNGenerateImageFeaturePrintRequestRevision2)
        #expect(request.imageCropAndScaleOption == .scaleFill)
        #expect(VisionFeaturePrintExtractor.cropAndScaleOption == .scaleFill)
    }

    @Test func fallsBackToRevision1WhenRevision2IsUnavailable() {
        let revision1 = VNGenerateImageFeaturePrintRequestRevision1
        let revision2 = VNGenerateImageFeaturePrintRequestRevision2
        #expect(VisionFeaturePrintExtractor.preferredRevision(supported: IndexSet([revision1])) == revision1)
        #expect(VisionFeaturePrintExtractor.preferredRevision(supported: IndexSet([revision1, revision2])) == revision2)
    }

    @Test func anOSWithoutRevision2GetsRevision1Requests() {
        let revision1 = VNGenerateImageFeaturePrintRequestRevision1
        let extractor = VisionFeaturePrintExtractor(supportedRevisions: IndexSet([revision1]))
        #expect(extractor.revision == revision1)
        #expect(extractor.makeRequest().revision == revision1)
    }

    @Test func eachRequestIsANewObject() {
        #expect(extractor.makeRequest() !== extractor.makeRequest())
    }

    // MARK: - Data to floats

    @Test func copiesFloatDataIntoAVector() throws {
        let vector: [Float] = [0.5, -1.25, 3, 1e-7]
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        #expect(try VisionFeaturePrintExtractor.floats(from: data, elementCount: 4, elementType: .float) == vector)
    }

    @Test func copiesMisalignedFloatData() throws {
        let vector: [Float] = [0.5, -1.25, 3, 1e-7]
        // One leading byte, then slicing it off: the floats start one byte past an aligned address.
        var padded = Data([0])
        vector.withUnsafeBufferPointer { padded.append($0) }
        let misaligned = padded.dropFirst()
        let isMisaligned = misaligned.withUnsafeBytes { bytes in
            Int(bitPattern: bytes.baseAddress) % MemoryLayout<Float>.alignment != 0
        }
        try #require(isMisaligned)

        let copied = try VisionFeaturePrintExtractor.floats(from: misaligned, elementCount: 4, elementType: .float)
        #expect(copied == vector)
    }

    @Test func rejectsDoubleAndUnknownElements() {
        let data = Data(count: 32)
        for elementType in [VNElementType.double, .unknown] {
            #expect(throws: FeaturePrintExtractionError.unsupportedElementType) {
                try VisionFeaturePrintExtractor.floats(from: data, elementCount: 4, elementType: elementType)
            }
        }
    }

    @Test func rejectsDataOfTheWrongSize() {
        #expect(throws: FeaturePrintExtractionError.sizeMismatch(expectedBytes: 16, actualBytes: 12)) {
            try VisionFeaturePrintExtractor.floats(from: Data(count: 12), elementCount: 4, elementType: .float)
        }
    }

    // MARK: - Real Vision

    @Test func extractsAFloatVectorTaggedWithItsRevision() throws {
        let extracted = try extractor.extract(from: image(0))
        #expect(extracted.revision == VNGenerateImageFeaturePrintRequestRevision2)
        #expect(!extracted.vector.isEmpty)
        let allFinite = extracted.vector.allSatisfy { $0.isFinite }
        #expect(allFinite)
    }

    @Test func vDSPDistanceMatchesVisionWithin1e4() throws {
        let first = try extractor.makeObservation(for: image(0))
        let second = try extractor.makeObservation(for: image(1))

        let visionDistance = try Self.visionDistance(first, second)
        let vectorDistance = VectorMath.euclideanDistance(try Self.vector(first), try Self.vector(second))

        #expect(visionDistance > 1e-3, "The two test images should not look alike")
        #expect(abs(visionDistance - vectorDistance) <= 1e-4)
    }

    @Test func theSameImageIsZeroApart() throws {
        let picture = try image(1)
        let first = try extractor.extract(from: picture)
        let second = try extractor.extract(from: picture)
        #expect(VectorMath.euclideanDistance(first.vector, second.vector) <= 1e-4)
    }

    @Test func orientationIsApplied() throws {
        // `.right` means "turn the pixels 90° clockwise to show the photo upright". Vision must see the same picture
        // as for pixels that were already turned.
        let pixels = try SyntheticImages.pattern(0)
        let rotated = try SyntheticImages.rotatedClockwise(pixels)
        let upright = try extractor.extract(from: LoadedImage(cgImage: rotated, orientation: .up))
        let oriented = try extractor.extract(from: LoadedImage(cgImage: pixels, orientation: .right))
        let ignored = try extractor.extract(from: LoadedImage(cgImage: pixels, orientation: .up))

        let orientedDistance = VectorMath.euclideanDistance(oriented.vector, upright.vector)
        let ignoredDistance = VectorMath.euclideanDistance(ignored.vector, upright.vector)
        #expect(orientedDistance < ignoredDistance)
        #expect(orientedDistance < 0.1)
    }

    // MARK: - Helpers

    /// A synthetic picture, upright.
    private func image(_ variant: Int) throws -> LoadedImage {
        LoadedImage(cgImage: try SyntheticImages.pattern(variant), orientation: .up)
    }

    /// The distance Vision itself reports between two observations.
    static func visionDistance(
        _ first: VNFeaturePrintObservation,
        _ second: VNFeaturePrintObservation
    ) throws -> Float {
        var distance: Float = 0
        try first.computeDistance(&distance, to: second)
        return distance
    }

    /// The observation as floats, converted the way the extractor does it.
    static func vector(_ observation: VNFeaturePrintObservation) throws -> [Float] {
        try VisionFeaturePrintExtractor.floats(
            from: observation.data,
            elementCount: observation.elementCount,
            elementType: observation.elementType
        )
    }
}

/// Distinct, asymmetric test pictures drawn in code, so no image files are bundled.
enum SyntheticImages {
    /// A 320×240 picture. Variants 0 and 1 look clearly different.
    static func pattern(_ variant: Int) throws -> CGImage {
        let context = try makeContext(width: 320, height: 240)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        if variant == 0 {
            // A red block in the top-left corner, a blue disc bottom-right and black diagonal stripes.
            context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 10, y: 150, width: 120, height: 80))
            context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
            context.fillEllipse(in: CGRect(x: 210, y: 10, width: 90, height: 90))
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.setLineWidth(6)
            for offset in stride(from: -240, through: 320, by: 40) {
                context.move(to: CGPoint(x: offset, y: 0))
                context.addLine(to: CGPoint(x: offset + 240, y: 240))
            }
            context.strokePath()
        } else {
            // Green horizontal bars and a yellow triangle.
            context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1))
            for row in stride(from: 0, to: 240, by: 48) {
                context.fill(CGRect(x: 0, y: row, width: 320, height: 20))
            }
            context.setFillColor(CGColor(red: 0.95, green: 0.85, blue: 0.1, alpha: 1))
            context.move(to: CGPoint(x: 160, y: 220))
            context.addLine(to: CGPoint(x: 60, y: 30))
            context.addLine(to: CGPoint(x: 260, y: 30))
            context.closePath()
            context.fillPath()
        }
        return try makeImage(context)
    }

    /// The same pixels turned 90° clockwise (what EXIF orientation `.right` asks a viewer to do).
    static func rotatedClockwise(_ image: CGImage) throws -> CGImage {
        let context = try makeContext(width: image.height, height: image.width)
        // In Core Graphics' y-up space, rotating by -90° turns clockwise; the translation moves the result back
        // onto the canvas. The image's left edge ends up at the top, its top edge on the right.
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try makeImage(context)
    }

    /// An RGBA bitmap context of the given size.
    private static func makeContext(width: Int, height: Int) throws -> CGContext {
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
        return context
    }

    /// The context's current contents as an image.
    private static func makeImage(_ context: CGContext) throws -> CGImage {
        guard let image = context.makeImage() else {
            throw CocoaError(.featureUnsupported)
        }
        return image
    }
}
