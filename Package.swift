// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FLX10Utility",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FLX10Utility", targets: ["FLX10Utility"]),
        .library(name: "FLX10Kit", targets: ["FLX10Kit"]),
    ],
    targets: [
        // Thin C shim over IOUSBDeviceInterface; the CFPlugIn UUID macros are not importable into Swift.
        .target(
            name: "CFLX10USB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "FLX10Kit",
            dependencies: ["CFLX10USB"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ImageIO")]
        ),
        .executableTarget(
            name: "FLX10Utility",
            dependencies: ["FLX10Kit"]
        ),
        .testTarget(
            name: "FLX10KitTests",
            dependencies: ["FLX10Kit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
