// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraMedicationList",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraMedicationList",
            targets: ["PildoraMedicationList"]
        ),
    ],
    targets: [
        .target(
            name: "PildoraMedicationList",
            path: "Sources/PildoraMedicationList"
        ),
        .testTarget(
            name: "PildoraMedicationListTests",
            dependencies: ["PildoraMedicationList"],
            path: "Tests/PildoraMedicationListTests"
        ),
    ]
)
