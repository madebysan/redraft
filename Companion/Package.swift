// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Companion",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Companion",
            dependencies: ["HotKey", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Companion",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            // Sparkle.framework is embedded in Contents/Frameworks by script/build_and_run.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "CompanionTests",
            dependencies: ["Companion"]
        )
    ]
)
