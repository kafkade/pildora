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
    dependencies: [
        // Shared SwiftUI design system: color/typography/spacing tokens and base
        // components used across all iOS features (issue #43).
        .package(path: "../../design-system/PildoraDesignSystem"),
    ],
    targets: [
        .target(
            name: "PildoraTodayView",
            dependencies: [
                .product(name: "PildoraDesignSystem", package: "PildoraDesignSystem"),
            ],
            path: "Sources/PildoraTodayView"
        ),
        .testTarget(
            name: "PildoraTodayViewTests",
            dependencies: ["PildoraTodayView"],
            path: "Tests/PildoraTodayViewTests"
        ),
    ]
)
