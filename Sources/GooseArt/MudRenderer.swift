import AppKit

/// Footprints stay procedural whatever the goose looks like — they are marks on
/// the screen, not part of the character. But they still have to match the goose's
/// medium: crisp pixel mud under a smooth goose, or smooth mud under a pixel
/// goose, reads as a bug either way.
public enum MudRenderer {
    private static let mud = NSColor(calibratedRed: 0.36, green: 0.24, blue: 0.13, alpha: 0.62)

    public static func drawFootprint(
        at point: CGPoint,
        facingLeft: Bool,
        isLeftFoot: Bool,
        style: ArtStyle
    ) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        mud.setFill()
        mud.setStroke()

        if style.isPixelArt {
            drawPixels(at: point, facingLeft: facingLeft, isLeftFoot: isLeftFoot, style: style, context: context)
        } else {
            drawCurves(at: point, facingLeft: facingLeft, isLeftFoot: isLeftFoot)
        }
    }

    // MARK: - Pixel mud

    /// A webbed foot pointing right: a heel pad on the left, three toes fanning
    /// out. Written as art rather than geometry, because at six pixels wide that is
    /// what it is — every square is a decision, so make them legible in the source.
    private static let footPattern = [
        ".....XX.",
        "..XXXXX.",
        "XXXXXX..",
        "XXXXXXXX",
        "XXXXXX..",
        "..XXXXX.",
        ".....XX.",
    ]

    private static func drawPixels(
        at point: CGPoint,
        facingLeft: Bool,
        isLeftFoot: Bool,
        style: ArtStyle,
        context: NSGraphicsContext
    ) {
        context.shouldAntialias = false

        let pixel = style.pixelSize
        let columns = footPattern.first?.count ?? 0
        let rows = footPattern.count

        // Every print snaps to the same grid. Without this each footprint lands on
        // its own sub-pixel offset and the trail looks ragged rather than stamped.
        let offsetY = point.y + (isLeftFoot ? pixel * 3 : -pixel * 3)
        let originX = style.snap(point.x - CGFloat(columns) * pixel / 2)
        let originY = style.snap(offsetY - CGFloat(rows) * pixel / 2)

        for (rowIndex, row) in footPattern.enumerated() {
            for (columnIndex, character) in row.enumerated() where character == "X" {
                // The pattern reads top-down; AppKit's y axis points up.
                let column = facingLeft ? columns - 1 - columnIndex : columnIndex
                let rect = NSRect(
                    x: originX + CGFloat(column) * pixel,
                    y: originY + CGFloat(rows - 1 - rowIndex) * pixel,
                    width: pixel,
                    height: pixel
                )
                rect.fill()
            }
        }
    }

    // MARK: - Smooth mud

    private static func drawCurves(at point: CGPoint, facingLeft: Bool, isLeftFoot: Bool) {
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y + (isLeftFoot ? 5 : -5))
        if facingLeft { transform.scaleX(by: -1, yBy: 1) }
        transform.concat()

        NSBezierPath(ovalIn: NSRect(x: -5, y: -4, width: 10, height: 8)).fill()
        for angle in [-0.55, 0.0, 0.55] as [CGFloat] {
            let toe = NSBezierPath()
            toe.move(to: .zero)
            toe.line(to: CGPoint(x: cos(angle) * 12, y: sin(angle) * 12))
            toe.lineWidth = 3
            toe.stroke()
        }
    }
}
