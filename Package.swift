// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassChatCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GlassChatCore", targets: ["GlassChatCore"])
    ],
    targets: [
        .target(
            name: "GlassChatCore",
            path: "GlassChat",
            exclude: [
                "App",
                "Features",
                "Resources"
            ]
        ),
        .testTarget(
            name: "GlassChatCoreTests",
            dependencies: ["GlassChatCore"],
            path: "GlassChatCoreTests"
        )
    ]
)
