// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiTarget",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MultiTarget", targets: ["Core", "Feature"])
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Feature", dependencies: ["Core"])
    ]
)
