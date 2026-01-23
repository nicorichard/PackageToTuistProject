// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WithTestTarget",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MyLib", targets: ["MyLib"])
    ],
    targets: [
        .target(name: "MyLib"),
        .testTarget(name: "MyLibTests", dependencies: ["MyLib"])
    ]
)
