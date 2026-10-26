// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapoCamViewer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TapoCamViewer", targets: ["TapoCamViewer"])
    ],
    targets: [
        .executableTarget(
            name: "TapoCamViewer",
            path: "Sources/TapoCamViewer"
        )
    ]
)
