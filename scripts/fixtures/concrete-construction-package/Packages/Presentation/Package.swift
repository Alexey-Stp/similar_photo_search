// Fixture (SPS-30): not built. Presentation declares a dependency on the Data package.
import PackageDescription

let package = Package(name: "Presentation", dependencies: [.package(path: "../Domain"), .package(path: "../Data")])
