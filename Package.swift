// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacIconSpice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IconSpiceCore", targets: ["IconSpiceCore"]),
        .executable(name: "MacIconSpice", targets: ["IconSpice"]),
        .executable(name: "iconspice", targets: ["IconSpiceCLI"])
    ],
    targets: [
        .target(name: "IconSpiceCore"),
        .executableTarget(name: "IconSpice", dependencies: ["IconSpiceCore"]),
        .executableTarget(name: "IconSpiceCLI", dependencies: ["IconSpiceCore"]),
        .testTarget(name: "IconSpiceCoreTests", dependencies: ["IconSpiceCore"]),
        .testTarget(name: "IconSpiceAppTests", dependencies: ["IconSpice"])
    ],
    swiftLanguageModes: [.v6]
)
