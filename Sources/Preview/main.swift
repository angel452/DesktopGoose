import AppKit
import Foundation
import GooseArt

// Renders the artwork to a PNG so it can be inspected without launching the app.
//
//   swift run Preview              # goose + mud + speech bubble, composed
//   swift run Preview --sheet      # the sprite sheet, magnified 8x on a checkerboard
//   swift run Preview --sheet 12   # a different magnification
//
// Pixel art is unreadable at 1:1 — a whole sheet is barely 200 pixels wide. Every
// defect found in this project's artwork was found by magnifying it and looking,
// not by a test.

let arguments = CommandLine.arguments
let spritesDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/Sprites", isDirectory: true)

guard let artwork = SpriteSheetArtwork(directory: spritesDirectory) else {
    FileHandle.standardError.write(Data("""
    No sprite sheet at \(spritesDirectory.path).
    Run `swift run BakeSprites` first.

    """.utf8))
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - Bitmap helpers

func render(width: Int, height: Int, _ body: () -> Void) -> NSBitmapImageRep? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context

    body()
    context.flushGraphics()
    return bitmap
}

func write(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try png.write(to: url)
    print("wrote \(url.path) at \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
}

// MARK: - Magnified sheet

func drawSheet(zoom: Int) throws {
    guard let image = NSImage(contentsOf: spritesDirectory.appendingPathComponent("goose.png")),
          let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }

    let width = source.width * zoom
    let height = source.height * zoom

    guard let bitmap = render(width: width, height: height, {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // A checkerboard, so transparent areas are obvious rather than assumed.
        let square = zoom * 4
        for row in 0...(height / square) {
            for column in 0...(width / square) {
                let shade: CGFloat = (row + column).isMultiple(of: 2) ? 0.86 : 0.76
                context.setFillColor(CGColor(gray: shade, alpha: 1))
                context.fill(CGRect(x: column * square, y: row * square, width: square, height: square))
            }
        }

        // Nearest neighbour, or the magnification would blur exactly what is being
        // inspected.
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    }) else { return }

    try write(bitmap, to: outputDirectory.appendingPathComponent("preview-sheet.png"))
}

// MARK: - Composed scene

func drawScene() throws {
    let style = ArtStyle(artwork: artwork)
    let density: CGFloat = 2
    let size = CGSize(width: 400, height: 220)

    guard let bitmap = render(
        width: Int(size.width * density),
        height: Int(size.height * density),
        {
        // Drawn at 2x so one artwork pixel covers the same ground it would on a
        // Retina display. Previewing at 1x would flatter the result.
        let scale = NSAffineTransform()
        scale.scale(by: density)
        scale.concat()

        NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.35, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        var isLeft = true
        for step in 0..<7 {
            MudRenderer.drawFootprint(
                at: CGPoint(x: 26 + CGFloat(step) * 17, y: 42),
                facingLeft: false,
                isLeftFoot: isLeft,
                style: style
            )
            isLeft.toggle()
        }

        let feet = CGPoint(x: 170, y: 36)
        let gooseHeight = artwork.frameSize.height - artwork.anchor.y

        let text = SpeechBubble.placeholderText()
        let content = CGSize(width: ceil(text.size().width), height: ceil(text.size().height))
        let bubbleSize = SpeechBubble.size(forContent: content, style: style)
        let bubble = NSRect(
            x: (feet.x - bubbleSize.width / 2).rounded(),
            y: (feet.y + gooseHeight + 6).rounded(),
            width: bubbleSize.width,
            height: bubbleSize.height
        )

        SpeechBubble.draw(
            in: bubble,
            tailSide: .bottom,
            tailCenterX: feet.x - bubble.minX,
            style: style
        )

        let textRect = SpeechBubble.contentRect(in: bubble, tailSide: .bottom, style: style)
        text.draw(in: NSRect(
            x: textRect.minX,
            y: textRect.midY - text.size().height / 2,
            width: textRect.width,
            height: text.size().height + 1
        ))

        // Two frames side by side: mid-stride and standing.
        artwork.draw(frame: 2, at: CGPoint(x: 90, y: 36), facingLeft: false)
        artwork.draw(frame: 8, at: feet, facingLeft: false)
        artwork.draw(frame: 2, at: CGPoint(x: 300, y: 36), facingLeft: true)
    }) else { return }

    try write(bitmap, to: outputDirectory.appendingPathComponent("preview-scene.png"))
}

// MARK: - Entry

if arguments.contains("--sheet") {
    let zoom = arguments.last.flatMap(Int.init) ?? 8
    try drawSheet(zoom: max(zoom, 1))
} else {
    try drawScene()
}
