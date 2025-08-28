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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1"),
        .package(url: "https://github.com/skiptools/swift-android-native.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NeedleTailLogger",
                dependencies: [
                    .product(name: "Logging", package: "swift-log", condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS])),
                    .product(name: "AndroidLogging", package: "swift-android-native", condition: .when(platforms: [.android]))
                ]
        ),
        .testTarget(
            name: "NeedleTailLoggerTests",
            dependencies: ["NeedleTailLogger"]),
    ]
)
