/// Translates between the brain's world and a y-down physical-pixel screen.
///
/// The brain thinks in logical points with y pointing up and its origin at the
/// bottom-left of its screen — the Mac's convention. Windows counts physical pixels
/// with y pointing down from the top-left. This is the one place that knows both.
public struct ScreenMapping: Equatable, Sendable {
    /// The screen's top-left on the desktop, in physical pixels.
    public let originX: Int
    public let originY: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Physical pixels per logical point.
    public let displayScale: Double

    public init(originX: Int, originY: Int, pixelWidth: Int, pixelHeight: Int, displayScale: Double) {
        self.originX = originX
        self.originY = originY
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.displayScale = displayScale > 0 ? displayScale : 1
    }

    /// The screen's size as the brain should see it, in logical points.
    public var logicalWidth: Double { Double(pixelWidth) / displayScale }
    public var logicalHeight: Double { Double(pixelHeight) / displayScale }

    /// A brain point to a desktop pixel, rounded so sprites never land between
    /// pixels and shimmer.
    public func toScreen(x: Double, y: Double) -> (x: Int, y: Int) {
        (
            originX + Int((x * displayScale).rounded()),
            originY + Int(((logicalHeight - y) * displayScale).rounded())
        )
    }

    /// A desktop pixel — the cursor, say — to a brain point.
    public func toBrain(x: Int, y: Int) -> (x: Double, y: Double) {
        (
            Double(x - originX) / displayScale,
            logicalHeight - Double(y - originY) / displayScale
        )
    }

    /// Converts logical points to physical pixels.
    public func pixels(_ points: Double) -> Int {
        Int((points * displayScale).rounded())
    }
}

/// Where a speech bubble goes relative to the goose, in y-down desktop pixels.
public struct BubblePlacement: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let tailSide: BubbleShape.TailSide
    /// The tail's centre, measured from the bubble's own left edge.
    public let tailCenterX: Int

    /// - Parameters:
    ///   - feetX, feetY: the goose's feet on the desktop.
    ///   - gooseHeight: how tall the goose stands, so the bubble clears its head.
    ///   - workArea: the usable screen, minus taskbar, the bubble must stay within.
    public init(
        width: Int,
        height: Int,
        feetX: Int,
        feetY: Int,
        gooseHeight: Int,
        gap: Int,
        pixel: Int,
        workArea: PixelRect
    ) {
        // Speak upwards. Too near the top and there is no room, so the bubble drops
        // below the feet and the tail flips over.
        let headY = feetY - gooseHeight - gap
        let fitsAbove = headY - height >= workArea.y
        tailSide = fitsAbove ? .bottom : .top
        y = fitsAbove ? headY - height : feetY + gap

        let left = min(max(feetX - width / 2, workArea.x), workArea.maxX - width)
        x = left

        // The tail keeps pointing at the goose even when the bubble has been pushed
        // sideways to stay on screen.
        let range = BubbleShape.tailRange(width: width, pixel: pixel)
        tailCenterX = min(max(feetX - left, range.lowerBound), range.upperBound)
    }
}

/// Where the dragged meme window goes, beside the goose on the ground line.
public enum MemePlacement {
    /// The largest edge a meme is shown at, in logical points.
    public static let maximumEdge = 300.0

    /// Fits an image inside the maximum edge without ever enlarging it.
    public static func fitted(width: Int, height: Int, displayScale: Double) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else {
            let fallback = Int((120 * displayScale).rounded())
            return (fallback, fallback)
        }
        let limit = maximumEdge * displayScale
        let scale = min(limit / Double(width), limit / Double(height), 1)
        return (
            max(Int((Double(width) * scale).rounded()), 1),
            max(Int((Double(height) * scale).rounded()), 1)
        )
    }

    /// The window's top-left so it sits on the trailing side of the goose with its
    /// bottom on the feet, reading as dragged rather than floating.
    public static func origin(
        feetX: Int,
        feetY: Int,
        onLeft: Bool,
        gooseHalfWidth: Int,
        gap: Int,
        windowWidth: Int,
        windowHeight: Int
    ) -> (x: Int, y: Int) {
        let clearance = gooseHalfWidth + gap
        let x = onLeft ? feetX - clearance - windowWidth : feetX + clearance
        return (x, feetY - windowHeight)
    }
}
