// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FileTriage", platforms: [.macOS(.v13)], products: [
    .executable(name: "FileTriage", targets: ["FileTriage"])
], targets: [
    .target(name: "FileTriageCore"),
    .executableTarget(name: "FileTriage", dependencies: ["FileTriageCore"]),
    .testTarget(name: "FileTriageCoreTests", dependencies: ["FileTriageCore"])
])
