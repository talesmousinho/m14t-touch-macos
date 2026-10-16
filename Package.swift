// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "M14tTouch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "M14tTouchCore", targets: ["M14tTouchCore"]),
        .executable(name: "m14ttouch", targets: ["M14tTouchCLI"]),
        .executable(name: "M14tTouchApp", targets: ["M14tTouchApp"])
    ],
    targets: [
        .target(
            name: "M14tTouchCore",
            path: "Sources/M14tTouch",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "M14tTouchCLI",
            dependencies: ["M14tTouchCore"],
            path: "Sources/M14tTouchCLI"
        ),
        .executableTarget(
            name: "M14tTouchApp",
            dependencies: ["M14tTouchCore"],
            path: "Sources/M14tTouchApp"
        ),
        .testTarget(
            name: "M14tTouchTests",
            dependencies: ["M14tTouchCore"],
            path: "Tests/M14tTouchTests"
        )
    ]
)
