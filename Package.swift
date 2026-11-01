// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanobrewUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NanobrewKit"),
        .executableTarget(name: "NanobrewUI", dependencies: ["NanobrewKit"]),
        .testTarget(name: "NanobrewKitTests", dependencies: ["NanobrewKit"]),
    ]
)
