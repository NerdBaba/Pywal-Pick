// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PywalPick",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PywalPick", targets: ["App"])
    ],
    targets: [
        .target(
            name: "PywalPick",
            dependencies: [],
            path: "Sources/PywalPick",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "App",
            dependencies: ["PywalPick"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "PywalPickTests",
            dependencies: ["PywalPick"],
            path: "Tests/ImagePickerTests"
        ),
    ]
)
