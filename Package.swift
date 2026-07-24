// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-pptx",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-pptx", type: .dynamic, targets: ["osaurus_pptx"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_pptx",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_pptx"
        ),
        .testTarget(
            name: "osaurus_pptx_tests",
            dependencies: [
                "osaurus_pptx",
                .product(name: "OsaurusPluginTestSupport", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_pptx_tests"
        )
    ]
)
