// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snapzify",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Snapzify", targets: ["Snapzify"])
    ],
    targets: [
        .target(
            name: "Snapzify",
            path: "Sources/Snapzify"
        )
    ]
)
