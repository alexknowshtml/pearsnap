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
    targets: [
        .executableTarget(
            name: "Pearsnap",
            path: "Sources"
        )
    ]
)
