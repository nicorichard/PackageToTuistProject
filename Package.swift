// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PackageToTuistProject",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "PackageToTuistProject",
            targets: ["PackageToTuistProject"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "PackageToTuistProject",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "PackageToTuistProjectTests",
            dependencies: ["PackageToTuistProject"]
        ),
    ]
)
