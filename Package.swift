// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBrow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NotchBrow", targets: ["NotchBrow"])],
    targets: [
        .target(name: "NotchBrowCore"),
        .executableTarget(name: "NotchBrow", dependencies: ["NotchBrowCore"], exclude: ["Resources"]),
        .executableTarget(name: "NotchBrowChecks", dependencies: ["NotchBrowCore"], path: "Tests/NotchBrowCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
