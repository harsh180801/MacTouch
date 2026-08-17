// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTouch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MacTouchCore", targets: ["MacTouchCore"]),
        .executable(name: "MacTouchProbe", targets: ["MacTouchProbe"]),
        .executable(name: "MacTouchApp", targets: ["MacTouchApp"])
    ],
    targets: [
        .target(
            name: "MacTouchCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MacTouchProbe",
            dependencies: ["MacTouchCore"]
        ),
        .executableTarget(
            name: "MacTouchApp",
            dependencies: ["MacTouchCore"]
        ),
        .testTarget(
            name: "MacTouchCoreTests",
            dependencies: ["MacTouchCore"]
        )
    ]
)
