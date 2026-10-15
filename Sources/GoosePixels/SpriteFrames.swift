import GooseCore

/// How big everything is on a screen measured in physical pixels.
///
/// Pixel art only stays crisp when one artwork pixel covers a whole number of
/// screen pixels, so the sheet's points-per-pixel ratio is rounded to an integer
/// block for the current display scale. At 100 % the 1.5-point art pixel becomes a
/// 2 × 2 block; at 200 % a 3 × 3 one.
public struct PixelMetrics: Equatable, Sendable {
    /// Screen pixels per artwork pixel, on each axis.
    public let artPixel: Int
    /// Screen pixels per logical point, e.g. 1.5 at 150 % scaling.
    public let displayScale: Double
    /// One frame on screen, in physical pixels.
    public let frameWidth: Int
    public let frameHeight: Int
    /// Where the feet sit, from the frame's left and bottom, in physical pixels.
    public let anchorX: Int
    public let anchorY: Int

    public init(manifest: SpriteSheetManifest, displayScale: Double) {
        let pointsPerSourcePixel = manifest.scale > 0 ? 1 / manifest.scale : 1
        let scale = displayScale > 0 ? displayScale : 1
        artPixel = max(1, Int((pointsPerSourcePixel * scale).rounded()))
        self.displayScale = scale
        frameWidth = manifest.frameWidth * artPixel
        frameHeight = manifest.frameHeight * artPixel
        anchorX = Int(manifest.anchorX.rounded()) * artPixel
        anchorY = Int(manifest.anchorY.rounded()) * artPixel
    }

    /// Half the window the goose lives in. Mirroring flips the frame around the
    /// feet, so the window is as wide as twice the larger side.
    public var halfWidth: Int { max(anchorX, frameWidth - anchorX) }

    /// The goose's window, sized so the feet stay centred whichever way it faces.
    public var windowWidth: Int { halfWidth * 2 }
    public var windowHeight: Int { frameHeight }

    /// The feet inside that window, y-down.
    public var feetInWindow: (x: Int, y: Int) { (halfWidth, frameHeight - anchorY) }

    /// How tall the goose stands above its feet.
    public var gooseHeight: Int { frameHeight - anchorY }

    /// Where a frame's top-left goes inside the goose window, so the feet land on
    /// `feetInWindow` whether or not the frame is mirrored.
    public func frameOrigin(facingLeft: Bool) -> (x: Int, y: Int) {
        let leftOfFeet = facingLeft ? frameWidth - anchorX : anchorX
        return (halfWidth - leftOfFeet, 0)
    }
}

/// Slices a decoded sprite sheet into one image per frame.
public enum SpriteFrames {
    /// Frames run left to right, top to bottom — the convention every sprite
    /// editor exports.
    ///
    /// A frame that runs past the sheet's edge keeps its slot, holding whatever
    /// part of it the sheet has, so clip frame numbers never shift.
    public static func slice(_ sheet: PixelImage, manifest: SpriteSheetManifest) -> [PixelImage] {
        let columns = max(manifest.columns, 1)
        let width = manifest.frameWidth
        let height = manifest.frameHeight
        guard width > 0, height > 0 else { return [] }
        let rows = sheet.height / height
        guard rows > 0 else { return [] }

        return (0..<(rows * columns)).map { index in
            let x = (index % columns) * width
            let y = (index / columns) * height
            if let frame = sheet.cropped(x: x, y: y, width: width, height: height) {
                return frame
            }
            var partial = PixelCanvas(width: width, height: height)
            partial.blit(sheet, x: -x, y: -y)
            return partial.image
        }
    }
}
