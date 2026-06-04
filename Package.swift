// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// swift-android-native 1.4+ transitively pulls swift-jni and does not build on Linux hosts.
// Default resolution skips it (Android trait). Skip Android builds set SKIP_BRIDGE (see pqs-rtc).
let enableAndroidViaSkip = (Context.environment["SKIP_BRIDGE"] ?? "0") != "0"

var needleTailLoggerDependencies: [Target.Dependency] = [
    .product(
        name: "Logging",
        package: "swift-log",
        condition: .when(platforms: [.iOS, .macOS, .tvOS, .watchOS, .linux])
    ),
]

if enableAndroidViaSkip {
    needleTailLoggerDependencies.append(
        .product(
            name: "AndroidLogging",
            package: "swift-android-native",
            condition: .when(platforms: [.android])
        )
    )
} else {
    needleTailLoggerDependencies.append(
        .product(
            name: "AndroidLogging",
            package: "swift-android-native",
            condition: .when(platforms: [.android], traits: ["Android"])
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
    traits: [
        .trait(name: "Android"),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/skiptools/swift-android-native.git", from: "1.4.3"),
    ],
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
