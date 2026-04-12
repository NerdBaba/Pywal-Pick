// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ImagePicker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ImagePicker", targets: ["App"])
    ],
    targets: [
        .target(
            name: "ImagePicker",
            dependencies: [],
            path: "Sources/ImagePicker",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "App",
            dependencies: ["ImagePicker"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ImagePickerTests",
            dependencies: ["ImagePicker"],
            path: "Tests/ImagePickerTests"
        ),
    ]
)
