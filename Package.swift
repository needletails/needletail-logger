// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "needletail-logger",
    platforms: [.iOS(.v13), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NeedleTailLogger",
            targets: ["NeedleTailLogger"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailLogger",
                dependencies: [
                    .product(name: "Logging", package: "swift-log")
                ]
        ),
        .testTarget(
            name: "NeedleTailLoggerTests",
            dependencies: ["NeedleTailLogger"]),
    ]
)
