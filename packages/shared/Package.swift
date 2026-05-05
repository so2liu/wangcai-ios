// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WorthSnapShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "WorthSnapShared", targets: ["WorthSnapShared"]),
        .executable(name: "WorthSnapSharedChecks", targets: ["WorthSnapSharedChecks"])
    ],
    targets: [
        .target(name: "WorthSnapShared"),
        .executableTarget(name: "WorthSnapSharedChecks", dependencies: ["WorthSnapShared"])
    ]
)
