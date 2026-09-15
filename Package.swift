// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NinhoCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "NinhoCore", targets: ["NinhoCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .target(name: "NinhoCore", dependencies: [
            "ZIPFoundation",
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows]))
        ]),
        .testTarget(name: "NinhoCoreTests", dependencies: ["NinhoCore", "ZIPFoundation"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
