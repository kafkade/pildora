// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraDataLayer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "PildoraDataLayer",
            targets: ["PildoraDataLayer"]
        ),
    ],
    dependencies: [
        // GRDB.swift provides the SQLite/SQLCipher integration layer: Codable
        // records, type-safe queries, and the DatabaseMigrator framework.
        //
        // SQLCipher encryption is enabled by building GRDB with the SQLCipher
        // backend and defining the `GRDBCIPHER` compilation condition on this
        // target (done in the Xcode app project). Command-line `swift test`
        // links plain SQLite; the encryption path is validated in the app.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "PildoraDataLayer",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PildoraDataLayer"
        ),
        .testTarget(
            name: "PildoraDataLayerTests",
            dependencies: [
                "PildoraDataLayer",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/PildoraDataLayerTests"
        ),
    ]
)
