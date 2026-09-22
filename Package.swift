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
    ],
    targets: [
        .target(
            name: "CarMediaCore",
            path: "Sources/CarMediaCore"
        ),
        .testTarget(
            name: "CarMediaCoreTests",
            dependencies: ["CarMediaCore"],
            path: "Tests/CarMediaCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
