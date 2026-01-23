// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WithDependencies",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "WithDependencies", targets: ["WithDependencies"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "WithDependencies",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
