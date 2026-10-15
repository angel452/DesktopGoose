/// Muddy footprints as pixel stamps, in a y-down screen space.
///
/// The same webbed foot the Mac draws, snapped to the goose's artwork-pixel grid so
/// the trail looks stamped rather than ragged.
public enum FootprintStamp {
    public static let mud = PixelColor(red: 92, green: 61, blue: 33, alpha: 158)

    /// A webbed foot pointing right: a heel pad on the left, three toes fanning
    /// out. Read top to bottom, exactly as it is drawn.
    static let pattern = [
        ".....XX.",
        "..XXXXX.",
        "XXXXXX..",
        "XXXXXXXX",
        "XXXXXX..",
        "..XXXXX.",
        ".....XX.",
    ]

    /// The rectangles that make one print around `x`, `y`.
    ///
    /// - Parameter pixel: screen pixels per artwork pixel.
    public static func rects(x: Int, y: Int, facingLeft: Bool, isLeftFoot: Bool, pixel: Int) -> [PixelRect] {
        let pixel = max(pixel, 1)
        let columns = pattern.first?.count ?? 0
        let rows = pattern.count

        // The left foot sits a little higher on screen than the right, so the two
        // feet read as a pair. Higher is a smaller y here.
        let footY = y + (isLeftFoot ? -pixel * 3 : pixel * 3)
        let originX = snap(x - columns * pixel / 2, to: pixel)
        let originY = snap(footY - rows * pixel / 2, to: pixel)

        var rects: [PixelRect] = []
        for (rowIndex, row) in pattern.enumerated() {
            for (columnIndex, character) in row.enumerated() where character == "X" {
                let column = facingLeft ? columns - 1 - columnIndex : columnIndex
                rects.append(PixelRect(
                    x: originX + column * pixel,
                    y: originY + rowIndex * pixel,
                    width: pixel,
                    height: pixel
                ))
            }
        }
        return rects
    }

    static func snap(_ value: Int, to grid: Int) -> Int {
        guard grid > 1 else { return value }
        // Floor division, so negative coordinates snap the same way as positive ones.
        let floored = value >= 0 ? value / grid : -((-value + grid - 1) / grid)
        let remainder = value - floored * grid
        return remainder * 2 >= grid ? (floored + 1) * grid : floored * grid
    }
}

/// The prints currently on screen, ageing out on their own.
public struct FootprintTrail: Sendable {
    public struct Print: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let facingLeft: Bool
        public let isLeftFoot: Bool
        public let bornAt: Double
    }

    public private(set) var prints: [Print] = []
    private var nextFootIsLeft = true
    public let limit: Int
    /// How long a print lingers, in seconds.
    public let lifetime: Double

    public init(limit: Int = 800, lifetime: Double = 10) {
        self.limit = limit
        self.lifetime = lifetime
    }

    /// Adds a print, alternating feet, and drops the oldest past the limit.
    public mutating func add(x: Int, y: Int, facingLeft: Bool, now: Double) {
        prints.append(Print(x: x, y: y, facingLeft: facingLeft, isLeftFoot: nextFootIsLeft, bornAt: now))
        nextFootIsLeft.toggle()
        if prints.count > limit { prints.removeFirst(prints.count - limit) }
    }

    /// Drops prints past their lifetime. Returns whether anything went.
    @discardableResult
    public mutating func prune(now: Double) -> Bool {
        // Prints are appended in time order, so the expired ones are at the front.
        let expired = prints.prefix { now - $0.bornAt >= lifetime }.count
        guard expired > 0 else { return false }
        prints.removeFirst(expired)
        return true
    }

    /// Paints every print onto `canvas`, offset so screen coordinates land on it.
    public func draw(on canvas: inout PixelCanvas, originX: Int = 0, originY: Int = 0, pixel: Int) {
        for print in prints {
            for rect in FootprintStamp.rects(
                x: print.x - originX,
                y: print.y - originY,
                facingLeft: print.facingLeft,
                isLeftFoot: print.isLeftFoot,
                pixel: pixel
            ) {
                canvas.fill(rect, color: FootprintStamp.mud)
            }
        }
    }
}
