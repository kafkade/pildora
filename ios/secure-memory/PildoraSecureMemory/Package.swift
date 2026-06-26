// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PildoraSecureMemory",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraSecureMemory",
            targets: ["PildoraSecureMemory"]
        ),
    ],
    targets: [
        .target(
            name: "PildoraSecureMemory",
            path: "Sources/PildoraSecureMemory"
        ),
        .testTarget(
            name: "PildoraSecureMemoryTests",
            dependencies: ["PildoraSecureMemory"],
            path: "Tests/PildoraSecureMemoryTests"
        ),
    ]
)
