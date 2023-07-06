// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mendoza",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", branch: "master"),
        .package(url: "https://github.com/Subito-it/Bariloche", branch: "master"),
        .package(url: "https://github.com/Subito-it/Shout.git", branch: "mendoza/stable"),
        .package(url: "https://github.com/Subito-it/XcodeProj.git", branch: "mendoza/stable"),
        .package(url: "https://github.com/jpsim/SourceKitten.git", branch: "main"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", branch: "master"),
    ],
    targets: [
        .target(name: "BuildTools", path: "BuildTools"),
        .executableTarget(
            name: "mendoza",
            dependencies: [
                "Bariloche",
                .product(name: "Shout", package: "Shout"),
                // .product(name: "Shout-Static", package: "Shout"),
                "XcodeProj",
                "KeychainAccess",
                .product(name: "SourceKittenFramework", package: "SourceKitten")
            ]
        ),
    ]
)
