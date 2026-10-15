/// A colour with straight (non-premultiplied) alpha, as a designer would write it.
public struct PixelColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Packed as premultiplied `0xAARRGGBB`, which on a little-endian machine is
    /// the B, G, R, A byte order a 32-bit Windows DIB expects.
    public var premultiplied: UInt32 {
        let a = UInt32(alpha)
        let r = UInt32(red) * a / 255
        let g = UInt32(green) * a / 255
        let b = UInt32(blue) * a / 255
        return a << 24 | r << 16 | g << 8 | b
    }

    public static let white = PixelColor(red: 255, green: 255, blue: 255)
}

/// An image held as premultiplied `0xAARRGGBB` pixels, rows top to bottom.
public struct PixelImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public internal(set) var pixels: [UInt32]

    public init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height, "pixel count does not match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Builds an image from straight RGBA bytes, the layout image decoders hand
    /// back, premultiplying on the way in so blending later is a single multiply.
    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        for index in pixels.indices {
            let byte = index * 4
            pixels[index] = PixelColor(
                red: rgba[byte],
                green: rgba[byte + 1],
                blue: rgba[byte + 2],
                alpha: rgba[byte + 3]
            ).premultiplied
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    public func pixel(x: Int, y: Int) -> UInt32 {
        pixels[y * width + x]
    }

    /// Resampled to `width` × `height` by nearest neighbour, which keeps pixel art
    /// hard-edged — used for the tray icon.
    public func scaledNearest(width: Int, height: Int) -> PixelImage {
        let width = max(width, 1)
        let height = max(height, 1)
        var scaled = [UInt32](repeating: 0, count: width * height)
        for row in 0..<height {
            let sourceRow = min(row * self.height / height, self.height - 1)
            for column in 0..<width {
                let sourceColumn = min(column * self.width / width, self.width - 1)
                scaled[row * width + column] = pixels[sourceRow * self.width + sourceColumn]
            }
        }
        return PixelImage(width: width, height: height, pixels: scaled)
    }

    /// Composited onto opaque white, for surfaces that cannot show transparency —
    /// a meme in an ordinary window, above all.
    public func flattenedOnWhite() -> PixelImage {
        let white = PixelColor.white.premultiplied
        return PixelImage(
            width: width,
            height: height,
            pixels: pixels.map { PixelCanvas.over($0, white) }
        )
    }

    /// A sub-rectangle, or `nil` when the rectangle leaves the image.
    public func cropped(x: Int, y: Int, width: Int, height: Int) -> PixelImage? {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x + width <= self.width, y + height <= self.height
        else { return nil }

        var cropped = [UInt32]()
        cropped.reserveCapacity(width * height)
        for row in y..<(y + height) {
            let start = row * self.width + x
            cropped.append(contentsOf: pixels[start..<(start + width)])
        }
        return PixelImage(width: width, height: height, pixels: cropped)
    }
}

/// A software drawing surface: fills and sprite blits with source-over blending.
///
/// Pixel art needs nothing more than rectangles and nearest-neighbour scaling, and
/// doing it here keeps the drawing testable without a window — the platform layer
/// only has to push the finished buffer to the screen.
public struct PixelCanvas: Sendable {
    public private(set) var image: PixelImage

    public var width: Int { image.width }
    public var height: Int { image.height }
    public var pixels: [UInt32] { image.pixels }

    public init(width: Int, height: Int) {
        image = PixelImage(
            width: width,
            height: height,
            pixels: [UInt32](repeating: 0, count: max(width, 0) * max(height, 0))
        )
    }

    public func pixel(x: Int, y: Int) -> UInt32 {
        image.pixel(x: x, y: y)
    }

    public mutating func clear() {
        for index in image.pixels.indices { image.pixels[index] = 0 }
    }

    /// Fills a rectangle, clipped to the canvas.
    public mutating func fill(_ rect: PixelRect, color: PixelColor) {
        let clipped = rect.intersection(PixelRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isEmpty else { return }
        let source = color.premultiplied

        for row in clipped.y..<clipped.maxY {
            let base = row * width
            for column in clipped.x..<clipped.maxX {
                image.pixels[base + column] = Self.over(source, image.pixels[base + column])
            }
        }
    }

    /// Draws `sprite` with its top-left at (`x`, `y`), each source pixel becoming a
    /// `scale` × `scale` block. `mirrored` flips it horizontally within its own box.
    public mutating func blit(_ sprite: PixelImage, x: Int, y: Int, scale: Int = 1, mirrored: Bool = false) {
        let scale = max(scale, 1)
        let box = PixelRect(x: x, y: y, width: sprite.width * scale, height: sprite.height * scale)
        let clipped = box.intersection(PixelRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isEmpty else { return }

        for row in clipped.y..<clipped.maxY {
            let sourceRow = (row - y) / scale
            let base = row * width
            for column in clipped.x..<clipped.maxX {
                var sourceColumn = (column - x) / scale
                if mirrored { sourceColumn = sprite.width - 1 - sourceColumn }
                let source = sprite.pixels[sourceRow * sprite.width + sourceColumn]
                guard source >> 24 != 0 else { continue }
                image.pixels[base + column] = Self.over(source, image.pixels[base + column])
            }
        }
    }

    /// Source-over for premultiplied pixels: `src + dst × (1 − srcAlpha)`.
    static func over(_ source: UInt32, _ destination: UInt32) -> UInt32 {
        let alpha = source >> 24
        if alpha == 255 { return source }
        if alpha == 0 { return destination }

        let keep = 255 - alpha
        var result: UInt32 = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            let s = (source >> UInt32(shift)) & 0xFF
            let d = (destination >> UInt32(shift)) & 0xFF
            result |= min(s + d * keep / 255, 255) << UInt32(shift)
        }
        return result
    }
}

/// An integer rectangle in a y-down space, the way Windows and bitmaps count.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersection(_ other: PixelRect) -> PixelRect {
        let left = max(x, other.x)
        let top = max(y, other.y)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        return PixelRect(x: left, y: top, width: max(right - left, 0), height: max(bottom - top, 0))
    }
}
