// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhereAmICLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "whereami-cli", targets: ["WhereAmICLI"])
    ],
    targets: [
        .executableTarget(
            name: "WhereAmICLI",
            path: ".",
            sources: ["main.swift"],
            swiftSettings: [
                .define("CLI_TARGET")
            ]
        )
    ]
)
