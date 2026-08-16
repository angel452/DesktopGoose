import AppKit
import GooseCore

/// How a sheet should be rasterised.
///
/// The two cases are not interchangeable settings on the same idea. Smooth art is
/// drawn large and scaled down with interpolation; pixel art is drawn at its
/// native grid and may only ever be scaled up by a whole number. Mixing the two
/// gives you a blurry sprite that shimmers as it moves.
public enum BakeStyle {
    /// Vector artwork rendered at a fraction of the size it was designed at.
    /// - Parameters:
    ///   - sizeMultiplier: how big it appears relative to its design size.
    ///   - pixelDensity: pixels per screen point. 2 for Retina.
    case smooth(sizeMultiplier: Double, pixelDensity: Double)

    /// Pixel artwork rendered one image pixel per artwork pixel, then displayed at
    /// `zoom` times its native size with interpolation off.
    /// - Parameters:
    ///   - zoom: whole-number magnification. Anything fractional destroys the grid.
    ///   - pixelDensity: pixels per screen point of the display. 2 for Retina.
    case pixels(zoom: Int, pixelDensity: Double)
}

/// Renders artwork into a sprite sheet plus manifest.
///
/// This is what turns "we have no art" into a working sprite pipeline: the engine
/// consumes genuine frames today, and better art later is a file swap.
public enum SpriteSheetBaker {
    public enum BakeError: Error, CustomStringConvertible {
        case couldNotCreateBitmap
        case couldNotEncodePNG

        public var description: String {
            switch self {
            case .couldNotCreateBitmap: return "Could not allocate the sprite sheet bitmap"
            case .couldNotEncodePNG: return "Could not encode the sprite sheet as PNG"
            }
        }
    }

    @discardableResult
    public static func bake(
        artwork: any GooseArtwork,
        style: BakeStyle,
        to directory: URL,
        columns: Int = 6
    ) throws -> SpriteSheetManifest {
        let renderScale: Double
        let manifestScale: Double
        let isPixelArt: Bool

        switch style {
        case let .smooth(sizeMultiplier, pixelDensity):
            // Draw big, display small: the sheet holds more pixels than points.
            renderScale = sizeMultiplier * pixelDensity
            manifestScale = pixelDensity
            isPixelArt = false

        case let .pixels(zoom, pixelDensity):
            // Draw once per artwork pixel. Displaying it `zoom` times larger means
            // the sheet holds *fewer* pixels than the points it covers, which is
            // exactly what a manifest scale below 1 encodes.
            renderScale = 1
            manifestScale = pixelDensity / Double(max(zoom, 1))
            isPixelArt = true
        }

        let frameCount = artwork.frameCount
        let rows = Int(ceil(Double(frameCount) / Double(columns)))

        let framePixelWidth = Int((artwork.frameSize.width * renderScale).rounded())
        let framePixelHeight = Int((artwork.frameSize.height * renderScale).rounded())

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: framePixelWidth * columns,
            pixelsHigh: framePixelHeight * rows,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw BakeError.couldNotCreateBitmap }

        try render(
            artwork: artwork,
            into: bitmap,
            frameCount: frameCount,
            columns: columns,
            rows: rows,
            scale: renderScale
        )

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw BakeError.couldNotEncodePNG
        }
        try png.write(to: directory.appendingPathComponent("goose.png"))

        let manifest = SpriteSheetManifest(
            image: "goose.png",
            frameWidth: framePixelWidth,
            frameHeight: framePixelHeight,
            columns: columns,
            scale: manifestScale,
            anchorX: Double(artwork.anchor.x) * renderScale,
            anchorY: Double(artwork.anchor.y) * renderScale,
            pixelArt: isPixelArt,
            clips: [GooseClip.walk, GooseClip.idle, GooseClip.drag, GooseClip.angryWalk, GooseClip.angryIdle]
                .compactMap { artwork.clip(named: $0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest)
            .write(to: directory.appendingPathComponent(SpriteSheetArtwork.manifestName))

        return manifest
    }

    private static func render(
        artwork: any GooseArtwork,
        into bitmap: NSBitmapImageRep,
        frameCount: Int,
        columns: Int,
        rows: Int,
        scale: Double
    ) throws {
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw BakeError.couldNotCreateBitmap
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        // Draw in the artwork's own units and let the transform scale up, so vector
        // art stays sharp at any bake resolution. At scale 1 this is a no-op, which
        // is what pixel art needs.
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: CGFloat(scale))
        scaleTransform.concat()

        let frameWidth = artwork.frameSize.width
        let frameHeight = artwork.frameSize.height

        for frame in 0..<frameCount {
            let column = CGFloat(frame % columns)
            // Frames run top to bottom, but the bitmap's origin is bottom-left.
            let row = CGFloat(rows - 1 - frame / columns)

            let feet = CGPoint(
                x: column * frameWidth + artwork.anchor.x,
                y: row * frameHeight + artwork.anchor.y
            )
            artwork.draw(frame: frame, at: feet, facingLeft: false)
        }

        context.flushGraphics()
    }
}
