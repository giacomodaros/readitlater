// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaderAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReaderAPI", targets: ["ReaderAPI"])
    ],
    targets: [
        .target(name: "ReaderAPI")
    ]
)
