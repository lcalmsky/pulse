// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pulse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pulse", targets: ["pulse"]),
    ],
    targets: [
        .target(name: "PulseCore"),
        .executableTarget(name: "pulse", dependencies: ["PulseCore"]),
        .executableTarget(name: "pulse-selftest", dependencies: ["PulseCore"]),
    ],
    swiftLanguageModes: [.v5]
)
