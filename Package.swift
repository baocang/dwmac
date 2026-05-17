// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "dwmac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dwmac", targets: ["dwmac"])
    ],
    targets: [
        .executableTarget(
            name: "dwmac",
            path: "Sources/dwmac",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "dwmacTests",
            dependencies: ["dwmac"],
            path: "Tests/dwmacTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
