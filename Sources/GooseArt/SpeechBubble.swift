import AppKit

/// A comic speech bubble, drawn in whatever medium the goose is using.
///
/// Every measurement below is expressed in **artwork pixels** via `ArtStyle`, so
/// the same code produces a chunky stepped bubble next to a pixel goose and a
/// smooth rounded one next to a vector goose.
public enum SpeechBubble {
    /// Which edge the tail hangs off, so the bubble can flip when there is no room
    /// above the goose.
    public enum TailSide {
        case bottom
        case top
    }

    // Sizes in artwork pixels.
    private static let border: CGFloat = 2
    private static let padding: CGFloat = 3
    private static let corner: CGFloat = 3
    private static let tailWidth: CGFloat = 9
    private static let tailHeight: CGFloat = 7

    private static let fill = NSColor.white
    private static let ink = NSColor(calibratedWhite: 0.11, alpha: 1)

    /// A line styled to match the bubble — heavy, centred, ink on white. Anything
    /// drawn inside a bubble should go through here so the typography lives in one
    /// place; a second copy stops agreeing the first time the font changes.
    public static func text(_ string: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ])
    }

    /// Total window size needed to wrap `contentSize`, tail included.
    public static func size(forContent contentSize: CGSize, style: ArtStyle) -> CGSize {
        let inset = style.pixels(border + padding) * 2
        return CGSize(
            width: style.snap(contentSize.width + inset),
            height: style.snap(contentSize.height + inset + style.pixels(tailHeight))
        )
    }

    /// Where the image or text goes, given the whole window's bounds.
    public static func contentRect(in bounds: NSRect, tailSide: TailSide, style: ArtStyle) -> NSRect {
        let inset = style.pixels(border + padding)
        let tail = style.pixels(tailHeight)

        return NSRect(
            x: bounds.minX + inset,
            y: bounds.minY + inset + (tailSide == .bottom ? tail : 0),
            width: bounds.width - inset * 2,
            height: bounds.height - inset * 2 - tail
        )
    }

    /// Horizontal range the tail may sit in, so it stays attached to the bubble
    /// when the window has been clamped against a screen edge.
    public static func tailRange(in width: CGFloat, style: ArtStyle) -> ClosedRange<CGFloat> {
        let half = style.pixels(tailWidth) / 2 + style.pixels(corner)
        guard width > half * 2 else { return (width / 2)...(width / 2) }
        return half...(width - half)
    }

    /// - Parameter tailCenterX: where the tail sits, measured from the bubble's own
    ///   left edge rather than in the caller's coordinate space.
    public static func draw(
        in bounds: NSRect,
        tailSide: TailSide,
        tailCenterX: CGFloat,
        style: ArtStyle
    ) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        context.shouldAntialias = !style.isPixelArt

        let tail = style.pixels(tailHeight)
        let body = NSRect(
            x: bounds.minX,
            y: bounds.minY + (tailSide == .bottom ? tail : 0),
            width: bounds.width,
            height: bounds.height - tail
        )
        let centerX = bounds.minX + style.snap(tailCenterX)
        let step = style.isPixelArt ? style.pixelSize : 1
        let inset = style.pixels(border)

        // Filled twice rather than stroked: an outline pass in ink, then the white
        // inset on top. Stroking a stepped path would soften exactly the edges
        // this style depends on.
        ink.setFill()
        shape(
            body: body,
            corner: style.pixels(corner),
            tailSide: tailSide,
            tailCenterX: centerX,
            tailWidth: style.pixels(tailWidth),
            tailHeight: tail,
            tailAnchor: tailSide == .bottom ? body.minY : body.maxY,
            step: step,
            style: style
        ).fill()

        // The white tail keeps its full height but starts one border in, so it
        // punches through the body's edge. Shortening it instead leaves the bubble
        // outlined straight across where the tail joins, and the tail reads as a
        // separate shape floating underneath.
        fill.setFill()
        shape(
            body: body.insetBy(dx: inset, dy: inset),
            corner: style.pixels(corner),
            tailSide: tailSide,
            tailCenterX: centerX,
            tailWidth: style.pixels(tailWidth) - inset * 2,
            tailHeight: tail,
            tailAnchor: tailSide == .bottom ? body.minY + inset : body.maxY - inset,
            step: step,
            style: style
        ).fill()
    }

    // MARK: - Geometry

    private static func shape(
        body: NSRect,
        corner: CGFloat,
        tailSide: TailSide,
        tailCenterX: CGFloat,
        tailWidth: CGFloat,
        tailHeight: CGFloat,
        tailAnchor: CGFloat,
        step: CGFloat,
        style: ArtStyle
    ) -> NSBezierPath {
        let path = NSBezierPath()

        if style.isPixelArt {
            // Two overlapping rectangles: the classic way to get cut corners on a
            // grid without a single curve.
            path.appendRect(NSRect(
                x: body.minX + corner, y: body.minY,
                width: body.width - corner * 2, height: body.height
            ))
            path.appendRect(NSRect(
                x: body.minX, y: body.minY + corner,
                width: body.width, height: body.height - corner * 2
            ))
        } else {
            path.append(NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner))
        }

        appendTail(
            to: path,
            anchorY: tailAnchor,
            side: tailSide,
            centerX: tailCenterX,
            width: tailWidth,
            height: tailHeight,
            step: step
        )

        return path
    }

    /// The tail narrows one step at a time, which is what makes it read as drawn on
    /// the same grid as everything else rather than pasted on.
    private static func appendTail(
        to path: NSBezierPath,
        anchorY: CGFloat,
        side: TailSide,
        centerX: CGFloat,
        width: CGFloat,
        height: CGFloat,
        step: CGFloat
    ) {
        guard width > 0, height > 0, step > 0 else { return }
        let rows = max(Int((height / step).rounded()), 1)

        for row in 0..<rows {
            let remaining = 1 - CGFloat(row) / CGFloat(rows)
            let rowWidth = max(width * remaining, step)
            let y = side == .bottom
                ? anchorY - CGFloat(row + 1) * step
                : anchorY + CGFloat(row) * step

            path.appendRect(NSRect(
                x: centerX - rowWidth / 2,
                y: y,
                width: rowWidth,
                height: step
            ))
        }
    }
}
