// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CiderApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CiderApp",
            path: "Sources/CiderApp"
        ),
    ]
)
