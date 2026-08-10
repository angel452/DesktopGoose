// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopGoose",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, testable behaviour. No AppKit, no windows, no clock of its own.
        .target(name: "GooseCore"),

        // How the goose looks: procedural drawing, sprite sheets, and the baker.
        // A library rather than app code, because BakeSprites needs it too.
        .target(
            name: "GooseArt",
            dependencies: ["GooseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The app: overlay window, run loop, sound, meme windows.
        .executableTarget(
            name: "DesktopGoose",
            dependencies: ["GooseCore", "GooseArt"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders the goose into a real sprite sheet.
        .executableTarget(
            name: "BakeSprites",
            dependencies: ["GooseCore", "GooseArt"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Renders the artwork to PNGs so it can be inspected without the app.
        .executableTarget(
            name: "Preview",
            dependencies: ["GooseCore", "GooseArt"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Runs as an executable, not a testTarget: XCTest and swift-testing both
        // require a full Xcode install. `swift run GooseCoreTests`
        .executableTarget(name: "GooseCoreTests", dependencies: ["GooseCore"]),
    ]
)
