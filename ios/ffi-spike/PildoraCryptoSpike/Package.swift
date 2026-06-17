// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

// IMPORTANT: Before building, run the XCFramework build script:
//   cd <repo-root>
//   ./ios/ffi-spike/build-xcframework.sh
//
// This generates:
//   ios/ffi-spike/generated/pildora_crypto_ffi.swift  (UniFFI bindings)
//   ios/ffi-spike/PildoraCryptoFFI.xcframework/       (compiled Rust library)

let package = Package(
    name: "PildoraCryptoSpike",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .executable(
            name: "PildoraCryptoSpike",
            targets: ["PildoraCryptoSpike"]
        ),
    ],
    targets: [
        // The compiled Rust crypto library as an XCFramework
        .binaryTarget(
            name: "PildoraCryptoFFI",
            path: "../PildoraCryptoFFI.xcframework"
        ),
        // The spike executable that validates the FFI bridge
        .executableTarget(
            name: "PildoraCryptoSpike",
            dependencies: ["PildoraCryptoFFI"],
            path: "Sources",
            sources: ["main.swift"],
            // The generated UniFFI Swift bindings are compiled alongside
            resources: [],
            swiftSettings: [
                .unsafeFlags([
                    "-import-objc-header",
                    // The UniFFI-generated Swift file is included directly
                ])
            ]
        ),
    ]
)
