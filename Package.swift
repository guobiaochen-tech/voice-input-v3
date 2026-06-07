// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceInput", targets: ["VoiceInput"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            dependencies: [],
            path: "Sources/VoiceInput"
        ),
    ]
)
