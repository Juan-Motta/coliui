// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ColiUI",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ColiUI", targets: ["ColiUI"]),
    ],
    dependencies: [
        // Terminal emulation for the container shell; the app target only, ColiUICore stays dependency-free.
        // 1.11.2 is the newest release without Metal shaders, which need Xcode to compile.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.11.2"),
    ],
    targets: [
        .target(name: "ColiUICore"),
        .executableTarget(name: "ColiUI", dependencies: ["ColiUICore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "ColiUICoreTests", dependencies: ["ColiUICore"]),
        .testTarget(name: "ColiUITests", dependencies: ["ColiUI", "ColiUICore"]),
    ]
)
