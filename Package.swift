// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// swift-android-native 1.4+ transitively pulls swift-jni and does not build on Linux hosts.
// Only declare it when Skip builds the Android bridge (SKIP_BRIDGE, see pqs-rtc).
let enableAndroidLogging = (Context.environment["SKIP_BRIDGE"] ?? "0") != "0"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
]

var needleTailLoggerDependencies: [Target.Dependency] = [
    .product(
        name: "Logging",
        package: "swift-log",
        condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .linux])
    ),
]

if enableAndroidLogging {
    packageDependencies.append(
        .package(url: "https://github.com/skiptools/swift-android-native.git", from: "1.4.3")
    )
    needleTailLoggerDependencies.append(
        .product(
            name: "AndroidLogging",
            package: "swift-android-native",
            condition: .when(platforms: [.android])
        )
    )
}

let package = Package(
    name: "needletail-logger",
    platforms: [.iOS(.v13), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(
            name: "NeedleTailLogger",
            targets: ["NeedleTailLogger"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "NeedleTailLogger",
            dependencies: needleTailLoggerDependencies
        ),
        .testTarget(
            name: "NeedleTailLoggerTests",
            dependencies: ["NeedleTailLogger"]),
    ]
)
