// swift-tools-version: 6.2
import PackageDescription

// Test the same core sources compiled by the app, without creating a second app target.
let package = Package(
    name: "MidokuDevelopment",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MidokuExtensions", targets: ["MidokuExtensions"])],
    targets: [
        .target(name: "MidokuExtensions", path: "Midoku/Extensions/Core"),
        .testTarget(
            name: "MidokuExtensionsTests",
            dependencies: ["MidokuExtensions"],
            path: "Tests/Extensions",
            resources: [.copy("Fixtures")]
        )
    ]
)
