// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Gozcu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Gozcu",
            path: "Sources/Gozcu"
        )
    ]
)
