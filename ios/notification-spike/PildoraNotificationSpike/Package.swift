// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PildoraNotificationSpike",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    targets: [
        .executableTarget(
            name: "PildoraNotificationSpike",
            path: "Sources"
        ),
    ]
)
