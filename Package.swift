// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Signalbox",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Signalbox", targets: ["Signalbox"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "SignalboxCore"),
        .executableTarget(
            name: "Signalbox",
            dependencies: ["SignalboxCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SignalboxCoreTests", dependencies: ["SignalboxCore"]),
        .testTarget(name: "SignalboxTests", dependencies: ["Signalbox"])
    ]
)
