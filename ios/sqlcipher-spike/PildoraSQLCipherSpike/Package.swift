// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraSQLCipherSpike",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "PildoraSQLCipherSpike",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources",
            swiftSettings: [
                // When linked against SQLCipher (via Xcode build settings or
                // CocoaPods), uncomment to enable encryption APIs:
                // .define("GRDBCIPHER"),
            ]
        ),
    ]
)
