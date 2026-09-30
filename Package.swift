// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmbiantMemory",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AmbiantMemory", targets: ["AmbiantMemory"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3"),
        .executableTarget(
            name: "AmbiantMemory",
            dependencies: ["CSQLite"],
            path: "Sources/AmbiantMemory"
        ),
        .testTarget(
            name: "AmbiantMemoryTests",
            dependencies: ["AmbiantMemory"],
            path: "Tests/AmbiantMemoryTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
