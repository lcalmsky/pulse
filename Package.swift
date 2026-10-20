// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "deadhd-bar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "deadhd-bar", targets: ["deadhd-bar"]),
    ],
    targets: [
        .target(name: "DeadhdBarCore"),
        .executableTarget(name: "deadhd-bar", dependencies: ["DeadhdBarCore"]),
        .executableTarget(name: "deadhd-bar-selftest", dependencies: ["DeadhdBarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
