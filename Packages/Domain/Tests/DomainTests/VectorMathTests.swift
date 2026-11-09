import Domain
import DomainTestSupport
import Foundation
import Testing

struct VectorMathTests {
    /// Identical vectors are exactly 0 apart.
    @Test func identicalVectorsAreZeroApart() {
        let vector: [Float] = [0.25, -1.5, 3, 0]
        #expect(VectorMath.euclideanDistance(vector, vector) == 0)
    }

    /// Distance and squared distance match a hand-computed 3-4-5 example.
    @Test func matchesTheTextbookDistance() {
        // (3, 4) apart: a 3-4-5 triangle.
        #expect(abs(VectorMath.euclideanDistance([1, 2], [4, 6]) - 5) < 1e-6)
        #expect(abs(VectorMath.euclideanDistanceSquared([1, 2], [4, 6]) - 25) < 1e-5)
    }

    /// The distance from a to b equals the distance from b to a.
    @Test func isSymmetric() {
        let lhs: [Float] = [0.1, 0.7, -0.3, 0.9]
        let rhs: [Float] = [0.4, -0.2, 0.5, 0.0]
        #expect(VectorMath.euclideanDistance(lhs, rhs) == VectorMath.euclideanDistance(rhs, lhs))
    }

    /// 768-element vectors (Revision 2 size) give the expected distance.
    @Test func handlesFeaturePrintSizedVectors() {
        // Revision 2 prints have 768 elements. Every element differs by 0.5, so the distance is 0.5 * sqrt(768).
        let lhs = [Float](repeating: 0.25, count: 768)
        let rhs = [Float](repeating: 0.75, count: 768)
        let expected = 0.5 * Float(768).squareRoot()
        #expect(abs(VectorMath.euclideanDistance(lhs, rhs) - expected) < 1e-4)
    }

    /// Two empty vectors are 0 apart.
    @Test func emptyVectorsAreZeroApart() {
        #expect(VectorMath.euclideanDistance([], []) == 0)
    }
}

struct FeaturePrintOutcomeTests {
    private let sample = FeaturePrint(assetID: "A", revision: 2, vector: [1, 2], assetModificationDate: nil)

    /// Only `.computed` exposes a feature print.
    @Test func onlyAComputedOutcomeHasAPrint() {
        #expect(FeaturePrintOutcome.computed(sample).featurePrint == sample)
        #expect(FeaturePrintOutcome.skipped(.iCloudOnly).featurePrint == nil)
        #expect(FeaturePrintOutcome.failed(.vision).featurePrint == nil)
    }

    /// The mock returns preset outcomes, skips unknown IDs and records requests.
    @Test func mockReturnsPresetOutcomesAndRecordsRequests() async throws {
        let service = MockFeaturePrintService(outcomes: ["A": .computed(sample), "B": .failed(.vision)])
        let assets = ["A", "B", "C"].map {
            PhotoAsset(id: $0, creationDate: nil, pixelWidth: 1, pixelHeight: 1, isFavorite: false, mediaSubtypes: [])
        }
        var outcomes: [FeaturePrintOutcome] = []
        for asset in assets {
            outcomes.append(try await service.featurePrint(for: asset))
        }
        #expect(outcomes == [.computed(sample), .failed(.vision), .skipped(.iCloudOnly)])
        #expect(await service.requestedAssetIDs == ["A", "B", "C"])
        #expect(service.revision == 2)
    }
}
