// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraNotificationScheduler",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "PildoraNotificationScheduler",
            targets: ["PildoraNotificationScheduler"]
        ),
    ],
    // Pure Foundation + UserNotifications: no GRDB, no SQLCipher, no FFI. The
    // planner is a deterministic computation layer and the platform bridge sits
    // behind a protocol seam, so the whole package is testable with plain
    // `swift test` on the command line and in CI — no entitlements or live
    // notification center required.
    targets: [
        .target(
            name: "PildoraNotificationScheduler",
            path: "Sources/PildoraNotificationScheduler"
        ),
        .testTarget(
            name: "PildoraNotificationSchedulerTests",
            dependencies: ["PildoraNotificationScheduler"],
            path: "Tests/PildoraNotificationSchedulerTests"
        ),
    ]
)
