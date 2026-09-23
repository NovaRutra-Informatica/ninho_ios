// swift-tools-version: 6.0
import PackageDescription

// Official, immutable llama.cpp release; model weights are never downloaded by this package.
let package = Package(
    name: "NinhoLlama",
    platforms: [.iOS("26.0")],
    products: [.library(name: "NinhoLlama", targets: ["NinhoLlama"])],
    targets: [
        .binaryTarget(name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10000/llama-b10000-xcframework.zip",
            checksum: "325b862774bfbb19d3002449d895b174f6f4c9a681bbd689d2c74c0c0b73d0bb"),
        .target(name: "NinhoLlama", dependencies: ["llama"]),
        .testTarget(name: "NinhoLlamaTests", dependencies: ["NinhoLlama"])
    ],
    swiftLanguageModes: [.v6]
)
