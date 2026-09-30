// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AmbiantMemoryMacOSHelper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MacOSHelperProtocol",
            targets: ["MacOSHelperProtocol"]
        ),
        .executable(
            name: "ambiant-memory-macos-helper",
            targets: ["AmbiantMemoryMacOSHelper"]
        )
    ],
    targets: [
        .target(
            name: "MacOSHelperProtocol",
            path: "Sources/Protocol"
        ),
        .executableTarget(
            name: "AmbiantMemoryMacOSHelper",
            dependencies: ["MacOSHelperProtocol"],
            path: "Sources/Helper"
        ),
        .testTarget(
            name: "MacOSHelperProtocolTests",
            dependencies: ["MacOSHelperProtocol"],
            path: "Tests/MacOSHelperProtocolTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
