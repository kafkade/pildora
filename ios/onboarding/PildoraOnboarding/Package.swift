// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraOnboarding",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraOnboarding",
            targets: ["PildoraOnboarding"]
        ),
    ],
    dependencies: [
        // Shared SwiftUI design system: color/typography/spacing tokens and the
        // base component library every iOS feature is built on (issue #43).
        .package(path: "../../design-system/PildoraDesignSystem"),
        // Move-only, zeroizing byte container (issue #40). Used to hold the
        // recovery key material so it is wiped from memory after the recovery
        // PDF is produced, per the issue's security notes.
        .package(path: "../../secure-memory/PildoraSecureMemory"),
    ],
    targets: [
        .target(
            name: "PildoraOnboarding",
            dependencies: [
                .product(name: "PildoraDesignSystem", package: "PildoraDesignSystem"),
                .product(name: "PildoraSecureMemory", package: "PildoraSecureMemory"),
            ],
            path: "Sources/PildoraOnboarding"
        ),
        .testTarget(
            name: "PildoraOnboardingTests",
            dependencies: [
                "PildoraOnboarding",
                .product(name: "PildoraSecureMemory", package: "PildoraSecureMemory"),
            ],
            path: "Tests/PildoraOnboardingTests"
        ),
    ]
)
