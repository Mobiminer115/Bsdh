// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "GameOptimizer",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "GameOptimizer", type: .dynamic, targets: ["GameOptimizer"])
    ],
    targets: [
        .target(
            name: "GameOptimizer",
            path: "Sources/GameOptimizer",
            exclude: ["Metal/UpscaleShaders.metal", "Example"],
            publicHeadersPath: "Public",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            cxxSettings: [.unsafeFlags(["-fobjc-arc"])]
        )
    ],
    cxxLanguageStandard: .cxx17
)
