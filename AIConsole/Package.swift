// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIConsole",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AIConsole", targets: ["AIConsoleApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "AIConsoleApp",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/AIConsoleApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "AIConsoleAppTests",
            dependencies: ["AIConsoleApp"],
            path: "Tests/AIConsoleAppTests"
        )
    ]
)
