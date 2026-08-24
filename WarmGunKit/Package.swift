// swift-tools-version: 6.0
// The pure logic of the phone satellite — what plays next, what to fetch
// ahead, what a tap means, how favorites and watch counts are kept — in a
// package with no UI or AVFoundation in it, so `swift test` runs it headlessly
// on the Mac in seconds. The app target holds only what needs the device.
import PackageDescription

let package = Package(
    name: "WarmGunKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WarmGunKit", targets: ["WarmGunKit"]),
    ],
    targets: [
        .target(name: "WarmGunKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "WarmGunKitTests",
            dependencies: ["WarmGunKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
