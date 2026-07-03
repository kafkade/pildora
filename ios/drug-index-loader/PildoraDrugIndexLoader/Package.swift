// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraDrugIndexLoader",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraDrugIndexLoader",
            targets: ["PildoraDrugIndexLoader"]
        ),
    ],
    dependencies: [
        // The read-only reader over the plaintext FTS5 index. The loader adds
        // the *tiered* behaviour (bundled core + downloaded full) around it.
        .package(path: "../../drug-index/PildoraDrugIndex"),
        // GRDB is used to validate a freshly downloaded index by opening it.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // System zlib, used to gunzip the downloaded `.gz` index on-device.
        // (Apple's Compression framework only does raw DEFLATE, not the gzip
        // container, so we use zlib's inflate with automatic header detection.)
        .systemLibrary(name: "Czlib", path: "Sources/Czlib"),
        .target(
            name: "PildoraDrugIndexLoader",
            dependencies: [
                "Czlib",
                .product(name: "PildoraDrugIndex", package: "PildoraDrugIndex"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PildoraDrugIndexLoader"
        ),
        .testTarget(
            name: "PildoraDrugIndexLoaderTests",
            dependencies: [
                "PildoraDrugIndexLoader",
                "Czlib",
                .product(name: "PildoraDrugIndex", package: "PildoraDrugIndex"),
            ],
            path: "Tests/PildoraDrugIndexLoaderTests"
        ),
    ]
)
