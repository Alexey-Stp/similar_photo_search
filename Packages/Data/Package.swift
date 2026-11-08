// swift-tools-version: 6.0
import PackageDescription

// The library/module is named `DataLayer` so it does not shadow `Foundation.Data`.
let package = Package(
    name: "Data",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DataLayer", targets: ["DataLayer"])
    ],
    dependencies: [
        .package(path: "../Domain")
    ],
    targets: [
        .target(
            name: "DataLayer",
            dependencies: [.product(name: "Domain", package: "Domain")]
        ),
        .testTarget(
            name: "DataTests",
            dependencies: [
                "DataLayer",
                .product(name: "Domain", package: "Domain")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
