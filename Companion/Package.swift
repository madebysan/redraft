// swift-tools-version: 5.9
import Foundation
import PackageDescription

// REDRAFT_APP_STORE=1 builds the sandboxed Mac App Store edition (script/build_app_store.sh):
// no Sparkle, no Accessibility API, selection checked by copying again. See Permissions.swift.
let appStore = ProcessInfo.processInfo.environment["REDRAFT_APP_STORE"] == "1"

var appDependencies: [Target.Dependency] = ["HotKey"]
if !appStore { appDependencies.append(.product(name: "Sparkle", package: "Sparkle")) }

let package = Package(
    name: "Companion",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1")]
        + (appStore ? [] : [.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.0")]),
    targets: [
        .executableTarget(
            name: "Companion",
            dependencies: appDependencies,
            path: "Sources/Companion",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            swiftSettings: appStore ? [.define("APP_STORE")] : [],
            // Sparkle.framework is embedded in Contents/Frameworks by script/build_and_run.sh.
            linkerSettings: appStore ? [] : [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "CompanionTests",
            dependencies: ["Companion"]
        )
    ]
)
