// swift-tools-version: 6.0
// The Swift SDK lives in packages/swift. This manifest sits at the repository root because
// Swift Package Manager resolves packages by repository URL and plain semantic-version tags.
import PackageDescription

let package = Package(
    name: "NeuralDefend",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "NeuralDefend", targets: ["NeuralDefend"])
    ],
    targets: [
        .target(
            name: "NeuralDefend",
            path: "packages/swift/Sources/NeuralDefend"
        ),
        .testTarget(
            name: "NeuralDefendTests",
            dependencies: ["NeuralDefend"],
            path: "packages/swift/Tests/NeuralDefendTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
