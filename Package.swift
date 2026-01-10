// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pearsnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Pearsnap", targets: ["Pearsnap"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Pearsnap",
            dependencies: ["Sparkle"],
            path: "Sources"
        )
    ]
)
