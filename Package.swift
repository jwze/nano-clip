// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanoClip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NanoClip", targets: ["NanoClip"])
    ],
    targets: [
        .target(
            name: "NanoClipCore",
            path: "Sources/NanoClipCore"
        ),
        .executableTarget(
            name: "NanoClip",
            dependencies: ["NanoClipCore"],
            path: "Sources/NanoClip"
        ),
    ]
)