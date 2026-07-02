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
    dependencies: [
        // The production encrypted persistence layer (SQLCipher/GRDB): the source
        // of truth for medications and inventory. Re-exported so app targets get
        // the model types via `import PildoraMedicationList`.
        .package(path: "../../data-layer/PildoraDataLayer"),
        // Local, plaintext FTS5 drug index that powers name autocomplete. Queries
        // never leave the device (zero-knowledge constraint).
        .package(path: "../../drug-index/PildoraDrugIndex"),
    ],
    targets: [
        .target(
            name: "PildoraMedicationList",
            dependencies: [
                .product(name: "PildoraDataLayer", package: "PildoraDataLayer"),
                .product(name: "PildoraDrugIndex", package: "PildoraDrugIndex"),
            ],
            path: "Sources/PildoraMedicationList"
        ),
        .testTarget(
            name: "PildoraMedicationListTests",
            dependencies: [
                "PildoraMedicationList",
                .product(name: "PildoraDataLayer", package: "PildoraDataLayer"),
            ],
            path: "Tests/PildoraMedicationListTests"
        ),
    ]
)
