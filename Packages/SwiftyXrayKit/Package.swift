// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyXrayKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
      .library(
        name: "SwiftyXrayKit",
        targets: ["SwiftyXrayKit"]
      ),
    ],
    dependencies: [],
    targets: [
      .binaryTarget(
        name: "LibXray",
        url: "https://github.com/dima-u/libXray-apple/releases/download/v26.3.27-ios/LibXray.xcframework.zip",
        checksum: "3a0f43e908e8acaa84b17467614cded31d12cc1918a4f89eb928caecfd8b2b09"
      ),
      .target(
        name: "SwiftyXrayKit",
        dependencies: ["LibXray"],
        path: "Sources/SwiftyXrayKit",
        // Swift 5 language mode: the kit's thread code predates Swift 6
        // strict-concurrency requirements (@Sendable Thread closures).
        swiftSettings: [
          .swiftLanguageMode(.v5)
        ],
        linkerSettings: [
          .linkedLibrary("resolv")
        ]
      )
    ]
)
