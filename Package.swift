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
            cxxSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedLibrary("objc")
            ]
        )
    ],
    cxxLanguageStandard: .gnucxx17
)
