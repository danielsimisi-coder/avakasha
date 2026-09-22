// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Avakasha", platforms: [.macOS(.v13)], products: [
    .executable(name: "Avakasha", targets: ["Avakasha"])
], targets: [
    .target(name: "AvakashaCore"),
    .executableTarget(name: "Avakasha", dependencies: ["AvakashaCore"]),
    .testTarget(name: "AvakashaCoreTests", dependencies: ["AvakashaCore"])
])
