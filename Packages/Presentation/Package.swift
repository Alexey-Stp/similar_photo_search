// swift-tools-version: 6.0
import PackageDescription

// Presentation depends on Domain only; it never sees the Data package.
let package = Package(
    name: "Presentation",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Presentation", targets: ["Presentation"])
    ],
    dependencies: [
        .package(path: "../Domain")
    ],
    targets: [
        .target(
            name: "Presentation",
            dependencies: [.product(name: "Domain", package: "Domain")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: [
                "Presentation",
                .product(name: "Domain", package: "Domain"),
                .product(name: "DomainTestSupport", package: "Domain")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
