// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SnapzifyCore",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SnapzifyCore",
            targets: ["SnapzifyCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        .target(
            name: "SnapzifyCore",
            dependencies: []
        ),
    ]
)