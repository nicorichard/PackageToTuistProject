// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BasicLibrary",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "BasicLibrary", targets: ["BasicLibrary"])
    ],
    targets: [
        .target(name: "BasicLibrary")
    ]
)
