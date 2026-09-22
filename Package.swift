// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Keepelix", platforms: [.macOS(.v13)], products: [
    .executable(name: "Keepelix", targets: ["Keepelix"])
], targets: [
    .target(name: "KeepelixCore"),
    .executableTarget(name: "Keepelix", dependencies: ["KeepelixCore"]),
    .testTarget(name: "KeepelixCoreTests", dependencies: ["KeepelixCore"])
])
