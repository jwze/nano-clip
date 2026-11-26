// swift-tools-version: 6.0
//
// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。
import PackageDescription

// The repository / project is called `nano-clip`; the SwiftPM package, product and app name are
// `NanoClip` (module identifiers cannot contain a hyphen anyway).
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