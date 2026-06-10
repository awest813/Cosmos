// swift-tools-version:5.9
import PackageDescription

// Cosmos desktop app shell (roadmap milestone 0.1).
//
// The SwiftUI sources live in `app/`. `swift build` produces the `Cosmos`
// executable; `scripts/build_cosmos_app.command` wraps it in a Cosmos.app
// bundle with the helper scripts in Resources.
let package = Package(
    name: "Cosmos",
    platforms: [
        // NavigationSplitView and the SwiftUI lifecycle used by the dashboard
        // require macOS 13+. The shell scripts themselves still target macOS 11.
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Cosmos",
            path: "app",
            exclude: ["cosmos"]
        ),
        .testTarget(
            name: "CosmosTests",
            dependencies: ["Cosmos"],
            path: "Tests/CosmosTests"
        ),
    ]
)
