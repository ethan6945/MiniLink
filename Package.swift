// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniLink",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MiniLink",
            path: "Sources/MiniLink"
        )
    ]
)
