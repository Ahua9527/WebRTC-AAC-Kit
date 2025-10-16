// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WebRTC-AAC-Kit",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "WebRTC",
            targets: ["WebRTC"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "WebRTC",
            url: "https://github.com/Ahua9527/WebRTC-AAC-Kit/releases/download/M142.0-aac/WebRTC-M142.0-aac.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    ]
)
