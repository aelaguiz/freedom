// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "codex-client",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CodexDock", targets: ["CodexDock"]),
    ],
    targets: [
        .target(
            name: "CodexDock",
            path: "CodexDock"
        ),
        .testTarget(
            name: "CodexDockTests",
            dependencies: ["CodexDock"],
            path: "CodexDockTests"
        ),
    ]
)
