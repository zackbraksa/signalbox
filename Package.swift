// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Signalbox", platforms: [.macOS(.v14)], products: [.executable(name: "Signalbox", targets: ["Signalbox"])], targets: [
    .target(name: "SignalboxCore"),
    .executableTarget(name: "Signalbox", dependencies: ["SignalboxCore"]),
    .testTarget(name: "SignalboxCoreTests", dependencies: ["SignalboxCore"]),
    .testTarget(name: "SignalboxTests", dependencies: ["Signalbox"])
])
