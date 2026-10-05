// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClickstreamSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ClickstreamSDK",
            targets: ["ClickstreamSDK"]
        ),
    ],
    targets: [
        .target(
            name: "ClickstreamSDK"
        ),
        .testTarget(
            name: "ClickstreamSDKTests",
            dependencies: ["ClickstreamSDK"]
        ),
    ]
)
