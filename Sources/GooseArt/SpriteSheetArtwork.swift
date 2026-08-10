import AppKit
import GooseCore

/// Draws the goose from a sprite sheet plus its JSON manifest.
///
/// The sheet is decoded once and sliced into one `CGImage` per frame at load
/// time. Drawing an `NSImage` sub-rectangle instead re-inflates the entire PNG on
/// every single draw — a profiler showed libz running inside the render loop.
public struct SpriteSheetArtwork: GooseArtwork {
    public static let manifestName = "goose.json"

    private let frames: [CGImage]
    private let manifest: SpriteSheetManifest

    public var frameSize: CGSize { manifest.frameSize }
    public var anchor: CGPoint { manifest.anchor }
    public var frameCount: Int { frames.count }
    public var isPixelArt: Bool { manifest.pixelArt }

    /// `scale` is pixels per point, so its reciprocal is how many points one
    /// source pixel covers: 1 / 0.667 = 1.5 for a 42px sheet magnified 3x on a
    /// 2x display.
    public var pixelSize: CGFloat {
        guard manifest.pixelArt, manifest.scale > 0 else { return 1 }
        return CGFloat(1 / manifest.scale)
    }

    /// Returns `nil` when the folder holds no usable sheet, so the caller can fall
    /// back to procedural art instead of shipping an invisible goose.
    public init?(directory: URL?) {
        guard let directory else { return nil }

        let manifestURL = directory.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SpriteSheetManifest.self, from: data),
              manifest.frameWidth > 0, manifest.frameHeight > 0, !manifest.clips.isEmpty,
              let image = NSImage(contentsOf: directory.appendingPathComponent(manifest.image)),
              let sheet = Self.decoded(image),
              case let frames = Self.slice(sheet, manifest: manifest),
              !frames.isEmpty
        else { return nil }

        self.manifest = manifest
        self.frames = frames
    }

    public func clip(named name: String) -> AnimationClip? {
        manifest.clip(named: name)
    }

    public func draw(frame: Int, at point: CGPoint, facingLeft: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let image = frames.indices.contains(frame) ? frames[frame] : frames[0]

        context.saveGState()
        defer { context.restoreGState() }

        // Smoothing turns pixel art into mush; vector-derived art needs it.
        context.interpolationQuality = manifest.pixelArt ? .none : .high

        context.translateBy(x: point.x, y: point.y)
        if facingLeft { context.scaleBy(x: -1, y: 1) }

        context.draw(image, in: CGRect(
            x: -anchor.x,
            y: -anchor.y,
            width: frameSize.width,
            height: frameSize.height
        ))
    }

    // MARK: - Loading

    /// Renders the sheet into a memory bitmap once. A `CGImage` handed over by an
    /// `NSImage` backed by a file stays lazy and decodes on demand, every time.
    private static func decoded(_ image: NSImage) -> CGImage? {
        guard let lazyImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: lazyImage.width,
            height: lazyImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(lazyImage, in: CGRect(x: 0, y: 0, width: lazyImage.width, height: lazyImage.height))
        return context.makeImage()
    }

    /// Frames run left to right, top to bottom — the convention every sprite editor
    /// exports, and the same origin `CGImage.cropping` uses.
    private static func slice(_ sheet: CGImage, manifest: SpriteSheetManifest) -> [CGImage] {
        let columns = max(manifest.columns, 1)
        let rows = sheet.height / manifest.frameHeight
        guard rows > 0 else { return [] }

        return (0..<(rows * columns)).compactMap { index in
            sheet.cropping(to: CGRect(
                x: (index % columns) * manifest.frameWidth,
                y: (index / columns) * manifest.frameHeight,
                width: manifest.frameWidth,
                height: manifest.frameHeight
            ))
        }
    }
}
