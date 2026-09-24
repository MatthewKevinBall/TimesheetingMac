// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JobTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "JobTimer", path: "Sources/JobTimer")
    ],
    swiftLanguageModes: [.v5]
)
