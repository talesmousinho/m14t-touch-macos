// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "M14tTouch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "m14ttouch", targets: ["M14tTouch"])
    ],
    targets: [
        .executableTarget(
            name: "M14tTouch",
            path: "Sources/M14tTouch",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "M14tTouchTests",
            dependencies: ["M14tTouch"],
            path: "Tests",
            exclude: ["GestureReplay/main.swift"],
            sources: ["M14tTouchTests", "GestureReplay/Checks.swift"]
        )
    ]
)
