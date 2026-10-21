// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CamBar",
    platforms: [.macOS(.v14)],
    targets: [
        // UI-independent logic: models, ffmpeg/ONVIF protocols, parsing, persistence.
        .target(name: "CamBarCore", path: "Sources/CamBarCore"),
        // The menu bar app (AppKit + SwiftUI).
        .executableTarget(name: "CamBar", dependencies: ["CamBarCore"], path: "Sources/CamBar"),
        // Self-checks for CamBarCore. XCTest and Swift Testing need a full Xcode install,
        // so these run as a plain executable: `swift run CamBarChecks`.
        .executableTarget(name: "CamBarChecks", dependencies: ["CamBarCore"], path: "Sources/CamBarChecks"),
    ]
)
