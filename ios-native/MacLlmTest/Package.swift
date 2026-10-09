// swift-tools-version: 5.9
// Mac command-line tool that runs the app's real CRM path (CrmEvidence.plan + LlamaRunner) on a
// prompt file, so the LLM behaviour can be tested without a phone. See README "Mac LLM test tool".
import PackageDescription

let package = Package(
    name: "llmtest",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../LlamaPackage")],
    targets: [
        .executableTarget(
            name: "llmtest",
            dependencies: [.product(name: "LlamaFramework", package: "LlamaPackage")],
            path: "Sources/llmtest")
    ]
)
