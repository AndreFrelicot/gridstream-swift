// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GridStreamKit",
    platforms: [
        .iOS(.v17),
        .macOS("15.6"),
    ],
    products: [
        .library(name: "GridStreamAPI", targets: ["GridStreamAPI"]),
    ],
    targets: [
        .target(name: "GridStreamAPI"),
        .testTarget(name: "GridStreamAPITests", dependencies: ["GridStreamAPI"]),
    ],
    swiftLanguageModes: [.v6]
)
