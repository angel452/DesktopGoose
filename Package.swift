// swift-tools-version: 6.0
import PackageDescription

// Shared by every platform: the goose's behaviour and its test suite.
var targets: [Target] = [
    // Pure, testable behaviour. No AppKit, no windows, no clock of its own.
    .target(name: "GooseCore"),

    // Pure software raster and screen layout in y-down physical pixels: what the
    // Windows app draws, kept here so it is tested on every platform.
    .target(name: "GoosePixels", dependencies: ["GooseCore", "CStbImage"]),

    // stb_image, vendored: PNG/JPEG/GIF/BMP decoding with no platform framework.
    .target(name: "CStbImage"),

    // Runs as an executable, not a testTarget: XCTest and swift-testing both
    // require a full Xcode install. `swift run GooseCoreTests`
    .executableTarget(name: "GooseCoreTests", dependencies: ["GooseCore", "GoosePixels"]),
]

#if os(macOS)
targets += [
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
]
#endif

#if os(Windows)
targets += [
    // The Windows app: layered overlay windows, a tray icon and a 60 Hz timer,
    // all a thin Win32 adapter around GooseCore and GoosePixels.
    .executableTarget(
        name: "DesktopGooseWin",
        dependencies: ["GooseCore", "GoosePixels"],
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: [
            .linkedLibrary("user32"),
            .linkedLibrary("gdi32"),
            .linkedLibrary("shell32"),
            .linkedLibrary("winmm"),
            // Release builds are a GUI app: no console window opens behind the
            // goose. Debug keeps the console so `swift run` still shows logs.
            .unsafeFlags(
                ["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"],
                .when(configuration: .release)
            ),
        ]
    ),
]
#endif

let package = Package(
    name: "DesktopGoose",
    platforms: [.macOS(.v14)],
    targets: targets
)
