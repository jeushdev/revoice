// swift-tools-version: 5.9
// Wraps llama.cpp's prebuilt XCFramework (Metal GPU included) so Xcode projects can add it as a
// local package. To upgrade: pick a release at https://github.com/ggml-org/llama.cpp/releases,
// change the tag in `url`, and update `checksum` with `swift package compute-checksum <zip>`.
// Slices shipped: ios-arm64 (device), macos. There is NO iOS simulator slice: test on a real iPhone.
import PackageDescription

let package = Package(
    name: "LlamaPackage",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "LlamaFramework", targets: ["LlamaFramework"])
    ],
    targets: [
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11531/llama-b11531-xcframework.zip",
            checksum: "db2a48c4909795633f5994c0056b30ee5e81d7b6d5993629bd677fe4636f959d"
        )
    ]
)
