// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipMac",
            path: "Sources/ClipMac",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon"),
                .linkedFramework("NaturalLanguage"),
            ]
        )
    ]
)
