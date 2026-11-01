// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanobrewUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NanobrewKit", resources: [.copy("Resources/Icons"), .copy("Resources/nanobrew-logo.png")]),
        .executableTarget(name: "NanobrewUI", dependencies: ["NanobrewKit"]),
        .testTarget(name: "NanobrewKitTests", dependencies: ["NanobrewKit"]),
    ]
)
