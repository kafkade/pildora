// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraTodayView",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraTodayView",
            targets: ["PildoraTodayView"]
        ),
    ],
    targets: [
        .target(
            name: "PildoraTodayView",
            path: "Sources/PildoraTodayView"
        ),
        .testTarget(
            name: "PildoraTodayViewTests",
            dependencies: ["PildoraTodayView"],
            path: "Tests/PildoraTodayViewTests"
        ),
    ]
)
