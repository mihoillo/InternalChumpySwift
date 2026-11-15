// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChumpyCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ChumpyCore", targets: ["ChumpyCore"])
    ],
    targets: [
        .target(
            name: "ChumpyCore",
            path: "Sources/ChumpyCore"
        ),
        .testTarget(
            name: "ChumpyCoreTests",
            dependencies: ["ChumpyCore"],
            path: "Tests/ChumpyCoreTests",
            resources: [
                .copy("Geodata")
            ]
        )
    ]
)
