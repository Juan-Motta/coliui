// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ColiUI",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ColiUI", targets: ["ColiUI"]),
    ],
    targets: [
        .target(name: "ColiUICore"),
        .executableTarget(name: "ColiUI", dependencies: ["ColiUICore"]),
        .testTarget(name: "ColiUICoreTests", dependencies: ["ColiUICore"]),
        .testTarget(name: "ColiUITests", dependencies: ["ColiUI", "ColiUICore"]),
    ]
)
