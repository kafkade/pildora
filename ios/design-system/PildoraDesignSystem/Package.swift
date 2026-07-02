// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraDesignSystem",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        // The Watch app shares this package's color tokens (Watch-specific
        // components are a separate concern — see issue #43).
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "PildoraDesignSystem",
            targets: ["PildoraDesignSystem"]
        ),
    ],
    targets: [
        .target(
            name: "PildoraDesignSystem",
            path: "Sources/PildoraDesignSystem"
        ),
        .testTarget(
            name: "PildoraDesignSystemTests",
            dependencies: ["PildoraDesignSystem"],
            path: "Tests/PildoraDesignSystemTests"
        ),
    ]
)
