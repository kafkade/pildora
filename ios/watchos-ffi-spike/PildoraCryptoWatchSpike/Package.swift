// swift-tools-version: 5.9
// Package.swift — watchOS FFI validation harness (issue #42).
//
// This package links the watchOS slices of PildoraCryptoFFI.xcframework and
// runs the FFI encrypt/decrypt validation as an XCTest bundle on the watchOS
// simulator.
//
// IMPORTANT: Before testing, build the XCFramework (with watchOS slices) and
// stage the generated bindings:
//   cd <repo-root>
//   ./ios/watchos-ffi-spike/run-watchos-tests.sh
//
// The run script builds ../ffi-spike/PildoraCryptoFFI.xcframework, copies the
// UniFFI-generated bindings into Tests/PildoraCryptoWatchTests/, boots a
// watchOS simulator, and runs `xcodebuild test`.

import PackageDescription

let package = Package(
    name: "PildoraCryptoWatchSpike",
    platforms: [
        // watchOS 10+ per docs/roadmap.md. Device coverage on stable Rust is
        // Apple Watch Series 9+/Ultra 2+ (aarch64-apple-watchos); Series 4–8
        // (arm64_32) is a documented follow-up — see README.md.
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "PildoraCryptoWatchKit",
            targets: ["PildoraCryptoWatchKit"]
        ),
    ],
    targets: [
        // The compiled Rust crypto library as an XCFramework (shared with the
        // iOS spike). Provides the watchos-arm64 and watchos-arm64-simulator
        // slices.
        .binaryTarget(
            name: "PildoraCryptoFFI",
            path: "../../ffi-spike/PildoraCryptoFFI.xcframework"
        ),
        // Library wrapping the UniFFI-generated bindings. Exposing a library
        // *product* gives the test scheme a concrete watchOS run destination.
        // The generated pildora_crypto_ffi.swift is copied into this target's
        // Sources by run-watchos-tests.sh.
        .target(
            name: "PildoraCryptoWatchKit",
            dependencies: ["PildoraCryptoFFI"],
            path: "Sources/PildoraCryptoWatchKit"
        ),
        // XCTest bundle exercising the FFI bridge on watchOS.
        .testTarget(
            name: "PildoraCryptoWatchTests",
            dependencies: ["PildoraCryptoWatchKit"],
            path: "Tests/PildoraCryptoWatchTests"
        ),
    ]
)
