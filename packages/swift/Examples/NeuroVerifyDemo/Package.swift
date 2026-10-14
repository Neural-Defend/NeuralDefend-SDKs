// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The SDK is the package at the repository root. SwiftPM names a local package after its
// directory, so the name is read from the checkout instead of being hard-coded.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NeuroVerifyDemo
    .deletingLastPathComponent()  // Examples
    .deletingLastPathComponent()  // swift
    .deletingLastPathComponent()  // packages
    .deletingLastPathComponent()

let package = Package(
    name: "NeuroVerifyDemo",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "NeuroVerifyDemo", targets: ["NeuroVerifyDemo"])
    ],
    dependencies: [
        .package(path: repositoryRoot.path)
    ],
    targets: [
        .target(
            name: "NeuroVerifyDemo",
            dependencies: [.product(name: "NeuralDefend", package: repositoryRoot.lastPathComponent)]
        ),
        .testTarget(
            name: "NeuroVerifyDemoTests",
            dependencies: ["NeuroVerifyDemo"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
