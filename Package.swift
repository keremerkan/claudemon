// swift-tools-version: 6.0
import PackageDescription

// Builds the shared core and the app, and runs the test suite, from the
// command line (`swift build`, `swift test`).
//
// The shippable product — including the WidgetKit extension and App Group —
// is built from the Xcode project (`Claudemon.xcodeproj`, maintained by hand);
// scripts/release-dmg.sh builds the release.
let package = Package(
    name: "Claudemon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Shared, network-free model + parsing + cache, used by app and widget.
        .target(
            name: "ClaudemonCore",
            path: "Sources/ClaudemonCore"
        ),
        // The menu-bar app target (links ClaudemonCore).
        .executableTarget(
            name: "Claudemon",
            dependencies: ["ClaudemonCore"],
            path: "Sources/Claudemon"
        ),
        // Parser/model tests, plus launch-priming tests for the app's UsageStore.
        .testTarget(
            name: "ClaudemonTests",
            dependencies: ["ClaudemonCore", "Claudemon"],
            path: "Tests/ClaudemonTests"
        )
    ]
)
