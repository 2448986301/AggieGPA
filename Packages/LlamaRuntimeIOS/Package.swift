// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LlamaRuntimeIOS",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "LlamaFramework", targets: ["llama"])
    ],
    targets: [
        .binaryTarget(name: "llama", path: "llama.xcframework")
    ]
)
