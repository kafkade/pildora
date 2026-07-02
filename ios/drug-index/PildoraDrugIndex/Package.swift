// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraDrugIndex",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraDrugIndex",
            targets: ["PildoraDrugIndex"]
        ),
    ],
    dependencies: [
        // GRDB provides the SQLite integration used to read the bundled,
        // plaintext FTS5 drug index. This index is public reference data (openFDA
        // / RxNorm) — it is NOT the encrypted vault store, so no SQLCipher here.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "PildoraDrugIndex",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PildoraDrugIndex"
        ),
        .testTarget(
            name: "PildoraDrugIndexTests",
            dependencies: [
                "PildoraDrugIndex",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/PildoraDrugIndexTests"
        ),
    ]
)
