import AppKit
import Foundation
import GooseArt

// Renders a goose into Assets/Sprites/{goose.png, goose.json}.
//
// Usage: swift run BakeSprites [output-directory] [pixel|smooth] [amount]
//
//   swift run BakeSprites                            # pixel art at 3x
//   swift run BakeSprites Assets/Sprites pixel 4     # chunkier pixel art
//   swift run BakeSprites Assets/Sprites smooth 0.5  # the vector goose, half size

let arguments = CommandLine.arguments

let outputDirectory: URL = arguments.count > 1
    ? URL(fileURLWithPath: arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Assets/Sprites", isDirectory: true)

let styleName = arguments.count > 2 ? arguments[2].lowercased() : "pixel"
let amount = arguments.count > 3 ? Double(arguments[3]) : nil

let artwork: any GooseArtwork
let style: BakeStyle
let columns: Int

if styleName == "smooth" {
    artwork = ProceduralArtwork()
    style = .smooth(sizeMultiplier: amount ?? 0.5, pixelDensity: 2)
    columns = 6
} else {
    artwork = PixelArtwork()
    // Whole numbers only. A fractional zoom makes some pixels wider than others.
    style = .pixels(zoom: Int(amount ?? 3), pixelDensity: 2)
    columns = 5
}

do {
    let manifest = try SpriteSheetBaker.bake(
        artwork: artwork,
        style: style,
        to: outputDirectory,
        columns: columns
    )

    print("Baked \(artwork.frameCount) \(styleName) frames to \(outputDirectory.path)")
    print("  sheet frame: \(manifest.frameWidth)x\(manifest.frameHeight) px")
    print("  on screen:   \(manifest.frameSize.width)x\(manifest.frameSize.height) pt")
    print("  interpolation: \(manifest.pixelArt ? "off (crisp pixels)" : "on (smooth)")")
    print("  clips: \(manifest.clips.map(\.name).joined(separator: ", "))")
} catch {
    FileHandle.standardError.write(Data("Bake failed: \(error)\n".utf8))
    exit(1)
}
