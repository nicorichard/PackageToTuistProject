// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiPlatform",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15)
    ],
    products: [
        .library(name: "MultiPlatform", targets: ["MultiPlatform"])
    ],
    targets: [
        .target(name: "MultiPlatform")
    ]
)
