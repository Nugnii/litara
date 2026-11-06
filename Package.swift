// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Litara",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LitaraCore", targets: ["LitaraCore"]),
    ],
    // обновления (B33, решение владельца 2026-11-06): стандартное окно Sparkle, проверка раз в день
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "LitaraCore", resources: [.copy("Resources")]),
        .executableTarget(name: "dictgen", dependencies: ["LitaraCore"]),
        .executableTarget(name: "Litara", dependencies: ["LitaraCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "LitaraCoreTests", dependencies: ["LitaraCore"], resources: [.copy("Fixtures")]),
    ]
)
