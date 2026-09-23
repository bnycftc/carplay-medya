// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CarMediaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CarMediaCore", targets: ["CarMediaCore"]),
        .library(name: "CarMediaKit", targets: ["CarMediaKit"]),
    ],
    targets: [
        .target(
            name: "CarMediaCore",
            path: "Sources/CarMediaCore"
        ),
        // App-level logic shared by the iOS app and CarPlay scene. Foundation only, so it
        // builds and tests on Windows like CarMediaCore.
        .target(
            name: "CarMediaKit",
            dependencies: ["CarMediaCore"],
            path: "Sources/CarMediaKit"
        ),
        .testTarget(
            name: "CarMediaCoreTests",
            dependencies: ["CarMediaCore"],
            path: "Tests/CarMediaCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CarMediaKitTests",
            dependencies: ["CarMediaKit"],
            path: "Tests/CarMediaKitTests"
        ),
    ]
)
