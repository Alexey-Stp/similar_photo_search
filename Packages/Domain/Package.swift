// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Domain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "DomainTestSupport", targets: ["DomainTestSupport"])
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "DomainTestSupport", dependencies: ["Domain"]),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain", "DomainTestSupport"],
            // The labelled calibration set (SPS-28): feature-print vectors only, no image pixels.
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
