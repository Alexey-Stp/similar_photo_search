import CoreGraphics
import Foundation
import Vision

/// What Vision says about one image's quality.
public struct VisionQualityResult: Sendable, Hashable {
    /// Mean face capture quality (0…1) over the detected faces, or `nil` if no face was found.
    public let faceQuality: Float?
    /// Aesthetics `overallScore` (-1…1), or `nil` before iOS 18.
    public let aesthetics: Float?
    /// Aesthetics `isUtility`, or `nil` before iOS 18.
    public let isUtility: Bool?

    /// Creates a result.
    public init(faceQuality: Float?, aesthetics: Float?, isUtility: Bool?) {
        self.faceQuality = faceQuality
        self.aesthetics = aesthetics
        self.isUtility = isUtility
    }
}

/// Runs the Vision quality requests on a loaded image. Synchronous: call it off the main thread.
public protocol QualityVisionExtracting: Sendable {
    /// Identifies the requests this extractor runs (revisions, aesthetics or not). Part of
    /// `QualityScorer.scoringVersion`, so measurements made with other requests are measured again.
    var signature: Int { get }

    /// Runs the requests on one image.
    /// - Throws: A Vision error.
    func analyze(_ image: LoadedImage) throws -> VisionQualityResult
}

/// `VNDetectFaceCaptureQualityRequest`, plus `VNCalculateImageAestheticsScoresRequest` on iOS 18 / macOS 15 and
/// later, in one `VNImageRequestHandler.perform`.
///
/// Every call creates its own requests and handler (Vision objects are never shared across threads) inside an
/// `autoreleasepool`.
public struct VisionQualityExtractor: QualityVisionExtracting {
    /// The face capture quality request revision: the newest one this OS supports, fixed for this extractor.
    public let faceRevision: Int
    /// Whether the aesthetics request runs (iOS 18 / macOS 15 and later).
    public let includesAesthetics: Bool

    /// `faceRevision * 10 + 1` with aesthetics, `+ 0` without.
    public var signature: Int { faceRevision * 10 + (includesAesthetics ? 1 : 0) }

    /// Creates an extractor for this OS.
    public init() {
        let aesthetics: Bool
        if #available(iOS 18, macOS 15, *) {
            aesthetics = true
        } else {
            aesthetics = false
        }
        self.init(
            supportedFaceRevisions: VNDetectFaceCaptureQualityRequest.supportedRevisions,
            includesAesthetics: aesthetics
        )
    }

    /// Creates an extractor for the given capabilities, so tests don't depend on the OS they run on. Aesthetics are
    /// only requested where the OS has them, whatever `includesAesthetics` says.
    init(supportedFaceRevisions: IndexSet, includesAesthetics: Bool) {
        self.faceRevision = supportedFaceRevisions.last ?? VNDetectFaceCaptureQualityRequest.defaultRevision
        self.includesAesthetics = includesAesthetics
    }

    /// Runs the face (and aesthetics) requests on `image`, respecting its orientation.
    public func analyze(_ image: LoadedImage) throws -> VisionQualityResult {
        try autoreleasepool {
            let faceRequest = VNDetectFaceCaptureQualityRequest()
            faceRequest.revision = faceRevision
            var requests: [VNRequest] = [faceRequest]
            let aestheticsRequest = makeAestheticsRequest()
            if let aestheticsRequest {
                requests.append(aestheticsRequest)
            }

            let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation, options: [:])
            try handler.perform(requests)

            let qualities = (faceRequest.results ?? []).compactMap(\.faceCaptureQuality)
            let (aesthetics, isUtility) = Self.aestheticsScores(of: aestheticsRequest)
            return VisionQualityResult(
                faceQuality: Self.mean(qualities),
                aesthetics: aesthetics,
                isUtility: isUtility
            )
        }
    }

    /// The mean of `values`, or `nil` if there are none (no faces is `nil`, never 0).
    static func mean(_ values: [Float]) -> Float? {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else { return nil }
        return finite.reduce(0, +) / Float(finite.count)
    }

    /// A new aesthetics request, or `nil` where it is not available or not wanted.
    private func makeAestheticsRequest() -> VNRequest? {
        guard includesAesthetics else { return nil }
        if #available(iOS 18, macOS 15, *) {
            return VNCalculateImageAestheticsScoresRequest()
        }
        return nil
    }

    /// The overall score and utility flag of a finished aesthetics request.
    private static func aestheticsScores(of request: VNRequest?) -> (Float?, Bool?) {
        guard let request else { return (nil, nil) }
        if #available(iOS 18, macOS 15, *),
           let observation = request.results?.first as? VNImageAestheticsScoresObservation {
            let score = observation.overallScore
            return (score.isFinite ? score : nil, observation.isUtility)
        }
        return (nil, nil)
    }
}
