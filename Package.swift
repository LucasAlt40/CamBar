// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CamBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CamBar", path: "Sources/CamBar")
    ]
)
