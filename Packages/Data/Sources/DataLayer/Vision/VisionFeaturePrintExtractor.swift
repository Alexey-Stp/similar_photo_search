import CoreGraphics
import Foundation
import Vision

/// A feature-print vector together with the Vision revision that produced it.
public struct ExtractedFeaturePrint: Sendable, Hashable {
    /// The `VNGenerateImageFeaturePrintRequest` revision.
    public let revision: Int
    /// The raw floats of the observation.
    public let vector: [Float]

    /// Creates an extracted print.
    public init(revision: Int, vector: [Float]) {
        self.revision = revision
        self.vector = vector
    }
}

/// Computes a feature print from a loaded image. Synchronous: call it off the main thread.
public protocol FeaturePrintExtracting: Sendable {
    /// The revision every extracted print has.
    var revision: Int { get }

    /// Computes the feature print of one image.
    /// - Throws: A Vision error (for example for an image that is too small) or `FeaturePrintExtractionError`.
    func extract(from image: LoadedImage) throws -> ExtractedFeaturePrint
}

/// Why a Vision observation could not be turned into a vector.
public enum FeaturePrintExtractionError: Error, Sendable, Hashable {
    /// Vision finished without a feature-print observation.
    case noObservation
    /// The observation holds `.double` or unknown elements; only `.float` is stored.
    case unsupportedElementType
    /// The observation's data does not hold `elementCount` floats.
    case sizeMismatch(expectedBytes: Int, actualBytes: Int)
}

/// `VNGenerateImageFeaturePrintRequest` with a fixed revision and crop-and-scale option.
///
/// Every call creates its own request and handler (Vision objects are never shared across threads) inside an
/// `autoreleasepool`.
public struct VisionFeaturePrintExtractor: FeaturePrintExtracting {
    /// Fixed so every print is comparable: the whole image is scaled to the model input, ignoring the aspect ratio
    /// (Vision's default). Changing it would make cached prints of the same revision meaningless.
    public static let cropAndScaleOption: VNImageCropAndScaleOption = .scaleFill

    public let revision: Int

    /// Creates an extractor with Revision 2, or Revision 1 if this OS does not support Revision 2.
    public init() {
        self.revision = Self.preferredRevision(supported: VNGenerateImageFeaturePrintRequest.supportedRevisions)
    }

    /// Revision 2 when supported, otherwise Revision 1.
    static func preferredRevision(supported: IndexSet) -> Int {
        supported.contains(VNGenerateImageFeaturePrintRequestRevision2)
            ? VNGenerateImageFeaturePrintRequestRevision2
            : VNGenerateImageFeaturePrintRequestRevision1
    }

    public func extract(from image: LoadedImage) throws -> ExtractedFeaturePrint {
        try autoreleasepool {
            let observation = try makeObservation(for: image)
            let vector = try Self.floats(
                from: observation.data,
                elementCount: observation.elementCount,
                elementType: observation.elementType
            )
            return ExtractedFeaturePrint(revision: revision, vector: vector)
        }
    }

    /// Runs Vision on one image, respecting its orientation. Tests use the observation to compare distances.
    func makeObservation(for image: LoadedImage) throws -> VNFeaturePrintObservation {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw FeaturePrintExtractionError.noObservation
        }
        return observation
    }

    /// A new request with this extractor's revision and the fixed crop-and-scale option.
    func makeRequest() -> VNGenerateImageFeaturePrintRequest {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        request.imageCropAndScaleOption = Self.cropAndScaleOption
        return request
    }

    /// Copies an observation's data into floats.
    ///
    /// Copies the bytes instead of binding the memory in place, so a misaligned `Data` can't trap.
    /// - Throws: `unsupportedElementType` unless `elementType` is `.float`; `sizeMismatch` if `data` does not hold
    ///   exactly `elementCount` floats.
    static func floats(from data: Data, elementCount: Int, elementType: VNElementType) throws -> [Float] {
        guard elementType == .float else {
            throw FeaturePrintExtractionError.unsupportedElementType
        }
        let expectedBytes = elementCount * MemoryLayout<Float>.size
        guard elementCount > 0, data.count == expectedBytes else {
            throw FeaturePrintExtractionError.sizeMismatch(expectedBytes: expectedBytes, actualBytes: data.count)
        }
        return [Float](unsafeUninitializedCapacity: elementCount) { buffer, initializedCount in
            initializedCount = data.copyBytes(to: buffer) / MemoryLayout<Float>.size
        }
    }
}
