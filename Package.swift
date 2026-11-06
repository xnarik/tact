// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Tact",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tact", targets: ["Tact"])],
    targets: [
        .target(name: "TactKit", swiftSettings: settings),
        .executableTarget(name: "Tact", dependencies: ["TactKit"], swiftSettings: settings),
        .executableTarget(name: "TactSnapshots", dependencies: ["TactKit"], swiftSettings: settings),
        .testTarget(name: "TactKitTests", dependencies: ["TactKit"], swiftSettings: settings),
    ]
)
