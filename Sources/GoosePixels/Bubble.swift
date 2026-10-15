/// The comic speech bubble, rasterised on the goose's artwork-pixel grid.
///
/// Mirrors the Mac's pixel-art bubble: cut corners from two overlapping rectangles,
/// an ink outline filled first, white on top, and a tail narrowing one step at a
/// time. Everything is y-down and measured in screen pixels.
public enum BubbleShape {
    /// Which edge the tail hangs off.
    public enum TailSide: Equatable, Sendable {
        case bottom
        case top
    }

    // Sizes in artwork pixels, the same as the Mac bubble.
    static let border = 2
    static let padding = 3
    static let corner = 3
    static let tailWidth = 9
    static let tailHeight = 7

    public static let ink = PixelColor(red: 28, green: 28, blue: 28)
    public static let paper = PixelColor.white

    /// Whole bubble size, tail included, for text of `contentWidth` × `contentHeight`.
    public static func size(contentWidth: Int, contentHeight: Int, pixel: Int) -> (width: Int, height: Int) {
        let pixel = max(pixel, 1)
        let inset = (border + padding) * pixel * 2
        return (
            roundUp(contentWidth + inset, to: pixel),
            roundUp(contentHeight + inset + tailHeight * pixel, to: pixel)
        )
    }

    /// Where the text goes inside a bubble of `width` × `height`.
    public static func contentRect(width: Int, height: Int, tailSide: TailSide, pixel: Int) -> PixelRect {
        let pixel = max(pixel, 1)
        let inset = (border + padding) * pixel
        let tail = tailHeight * pixel
        return PixelRect(
            x: inset,
            y: inset + (tailSide == .top ? tail : 0),
            width: width - inset * 2,
            height: height - inset * 2 - tail
        )
    }

    /// Horizontal range the tail may sit in, so it stays attached to the body.
    public static func tailRange(width: Int, pixel: Int) -> ClosedRange<Int> {
        let pixel = max(pixel, 1)
        let half = tailWidth * pixel / 2 + corner * pixel
        guard width > half * 2 else { return (width / 2)...(width / 2) }
        return half...(width - half)
    }

    /// Paints the bubble — body and tail, no text — onto a canvas of its own size.
    public static func draw(on canvas: inout PixelCanvas, tailSide: TailSide, tailCenterX: Int, pixel: Int) {
        let pixel = max(pixel, 1)
        let tail = tailHeight * pixel
        let body = PixelRect(
            x: 0,
            y: tailSide == .top ? tail : 0,
            width: canvas.width,
            height: canvas.height - tail
        )
        let centerX = FootprintStamp.snap(tailCenterX, to: pixel)
        let inset = border * pixel

        // Filled twice rather than stroked: ink first, then the white inset on top.
        // The white tail keeps its full height but starts one border in, so it
        // punches through the body's edge instead of floating under an outline.
        for rect in shape(
            body: body,
            tailSide: tailSide,
            centerX: centerX,
            tailWidth: tailWidth * pixel,
            tailAnchor: tailSide == .bottom ? body.maxY : body.y,
            pixel: pixel
        ) {
            canvas.fill(rect, color: ink)
        }

        let inner = PixelRect(
            x: body.x + inset,
            y: body.y + inset,
            width: body.width - inset * 2,
            height: body.height - inset * 2
        )
        for rect in shape(
            body: inner,
            tailSide: tailSide,
            centerX: centerX,
            tailWidth: tailWidth * pixel - inset * 2,
            tailAnchor: tailSide == .bottom ? body.maxY - inset : body.y + inset,
            pixel: pixel
        ) {
            canvas.fill(rect, color: paper)
        }
    }

    static func shape(
        body: PixelRect,
        tailSide: TailSide,
        centerX: Int,
        tailWidth: Int,
        tailAnchor: Int,
        pixel: Int
    ) -> [PixelRect] {
        let cut = corner * pixel
        var rects = [
            // Two overlapping rectangles: cut corners on a grid without a curve.
            PixelRect(x: body.x + cut, y: body.y, width: body.width - cut * 2, height: body.height),
            PixelRect(x: body.x, y: body.y + cut, width: body.width, height: body.height - cut * 2),
        ]

        guard tailWidth > 0 else { return rects }
        let rows = tailHeight
        for row in 0..<rows {
            let remaining = Double(rows - row) / Double(rows)
            let rowWidth = max(Int((Double(tailWidth) * remaining).rounded()), pixel)
            let y = tailSide == .bottom
                ? tailAnchor + row * pixel
                : tailAnchor - (row + 1) * pixel
            rects.append(PixelRect(x: centerX - rowWidth / 2, y: y, width: rowWidth, height: pixel))
        }
        return rects
    }

    static func roundUp(_ value: Int, to grid: Int) -> Int {
        guard grid > 1 else { return value }
        return (value + grid - 1) / grid * grid
    }
}
