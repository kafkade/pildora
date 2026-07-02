// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraScheduleEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraScheduleEngine",
            targets: ["PildoraScheduleEngine"]
        ),
    ],
    // Pure Foundation: no GRDB, no SQLCipher, no FFI. The engine is a
    // deterministic computation layer, so it stays dependency-free and is
    // testable with plain `swift test` on the command line and in CI.
    targets: [
        .target(
            name: "PildoraScheduleEngine",
            path: "Sources/PildoraScheduleEngine"
        ),
        .testTarget(
            name: "PildoraScheduleEngineTests",
            dependencies: ["PildoraScheduleEngine"],
            path: "Tests/PildoraScheduleEngineTests"
        ),
    ]
)
