import AppKit
import GooseCore

/// A goose designed for a 42×38 pixel grid.
///
/// This is deliberately **not** the vector goose made smaller. Pixel art cannot be
/// obtained by shrinking curves: antialiasing turns every edge into grey mush, and
/// anything thinner than a pixel — a 1.5pt outline, a feather crease — disappears
/// entirely. So the shapes here are chunky, every coordinate is a whole number,
/// and antialiasing is switched off before a single path is filled.
///
/// `frameSize` and `anchor` are in **native pixels**, not screen points. This type
/// exists to be baked; drawing it live would give a 42-point goose.
public struct PixelArtwork: GooseArtwork {
    public static let walkFrameCount = 8
    public static let idleFrameCount = 2
    public static let dragFrameCount = 6
    /// Angry variants reuse the walk and idle motion, tinted red with a frowning
    /// brow — the look the goose wears while it stares down and charges a cursor.
    public static let angryWalkFrameCount = walkFrameCount
    public static let angryIdleFrameCount = idleFrameCount

    public var frameCount: Int {
        Self.walkFrameCount + Self.idleFrameCount + Self.dragFrameCount
            + Self.angryWalkFrameCount + Self.angryIdleFrameCount
    }
    public var frameSize: CGSize { CGSize(width: 42, height: 38) }
    public var anchor: CGPoint { CGPoint(x: 18, y: 2) }
    public var isPixelArt: Bool { true }
    /// Its own units are already pixels; magnification happens at bake time.
    public var pixelSize: CGFloat { 1 }

    public init() {}

    public func clip(named name: String) -> AnimationClip? {
        switch name {
        case GooseClip.walk:
            return AnimationClip(
                name: GooseClip.walk,
                frames: Array(0..<Self.walkFrameCount),
                framesPerSecond: 10
            )
        case GooseClip.idle:
            return AnimationClip(
                name: GooseClip.idle,
                frames: Array(Self.walkFrameCount..<(Self.walkFrameCount + Self.idleFrameCount)),
                framesPerSecond: 2
            )
        case GooseClip.drag:
            let start = Self.walkFrameCount + Self.idleFrameCount
            return AnimationClip(
                name: GooseClip.drag,
                frames: Array(start..<(start + Self.dragFrameCount)),
                framesPerSecond: 6
            )
        case GooseClip.angryWalk:
            let start = Self.walkFrameCount + Self.idleFrameCount + Self.dragFrameCount
            return AnimationClip(
                name: GooseClip.angryWalk,
                frames: Array(start..<(start + Self.angryWalkFrameCount)),
                framesPerSecond: 10
            )
        case GooseClip.angryIdle:
            let start = Self.walkFrameCount + Self.idleFrameCount + Self.dragFrameCount
                + Self.angryWalkFrameCount
            return AnimationClip(
                name: GooseClip.angryIdle,
                frames: Array(start..<(start + Self.angryIdleFrameCount)),
                framesPerSecond: 2
            )
        default:
            return nil
        }
    }

    public func draw(frame: Int, at point: CGPoint, facingLeft: Bool) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        // The two lines the whole style depends on. Without them this is just a
        // blurry vector drawing at a small size.
        context.shouldAntialias = false
        context.imageInterpolation = .none

        let transform = NSAffineTransform()
        transform.translateX(by: point.x.rounded(), yBy: point.y.rounded())
        if facingLeft { transform.scaleX(by: -1, yBy: 1) }
        transform.concat()

        draw(pose: Pose.make(frame: frame))
    }

    // MARK: - Pose

    /// Every offset is rounded to a whole pixel. Sub-pixel motion in pixel art
    /// reads as the sprite vibrating, not moving.
    private struct Pose {
        /// Absolute x of each leg rather than a shared swing. Two legs mirrored
        /// around a pivot scissor correctly; two legs offset from fixed positions
        /// drift past each other and merge into one fat block at the extremes.
        let legFront: CGFloat
        let legBack: CGFloat
        let bodyBob: CGFloat
        let headLead: CGFloat
        /// How far the head strains downward. Only the drag pose uses it.
        let headDrop: CGFloat
        /// Red feathers and a frowning brow. The angry clips reuse the walk and idle
        /// motion below, just drawn in this mood.
        let angry: Bool

        /// Where both legs meet at the passing phase of the stride.
        private static let hip: CGFloat = -2

        static func make(frame: Int) -> Pose {
            let walk = PixelArtwork.walkFrameCount
            let idle = PixelArtwork.idleFrameCount
            let drag = PixelArtwork.dragFrameCount
            switch frame {
            case 0 ..< walk:
                return walking(index: frame, angry: false)
            case walk ..< (walk + idle):
                return idling(index: frame - walk, angry: false)
            case (walk + idle) ..< (walk + idle + drag):
                return dragging(index: frame - walk - idle)
            case (walk + idle + drag) ..< (walk + idle + drag + walk):
                return walking(index: frame - walk - idle - drag, angry: true)
            default:
                return idling(index: frame - walk - idle - drag - walk, angry: true)
            }
        }

        private static func walking(index: Int, angry: Bool) -> Pose {
            let phase = CGFloat(index) / CGFloat(PixelArtwork.walkFrameCount) * .pi * 2
            let swing = (sin(phase) * 3).rounded()
            return Pose(
                legFront: hip + swing,
                legBack: hip - swing,
                bodyBob: (abs(sin(phase * 2)) * 2).rounded(),
                headLead: (sin(phase) * 2).rounded(),
                headDrop: 0,
                angry: angry
            )
        }

        private static func idling(index: Int, angry: Bool) -> Pose {
            // Standing still means feet planted apart, not stacked on the hip.
            Pose(legFront: 1, legBack: -5, bodyBob: CGFloat(index), headLead: 0, headDrop: 0, angry: angry)
        }

        private static func dragging(index: Int) -> Pose {
            // Dragging the meme in: a braced, heaving trudge. Feet stamp wide and the
            // head strains low and forward toward the load, with none of the walk's
            // cheerful bounce.
            let phase = CGFloat(index) / CGFloat(PixelArtwork.dragFrameCount) * .pi * 2
            let stamp = (sin(phase) * 2).rounded()
            return Pose(
                legFront: hip + stamp + 3,
                legBack: hip - stamp - 3,
                bodyBob: 0,
                headLead: (1 + sin(phase)).rounded(),
                headDrop: (2 + abs(sin(phase)) * 2).rounded(),
                angry: false
            )
        }
    }

    // MARK: - Palette

    /// No outline colour. The reference silhouette is pure white, and the contact
    /// shadow is what keeps it readable on a light desktop.
    private static let feather = NSColor(calibratedWhite: 1, alpha: 1)
    private static let bill = NSColor(calibratedRed: 0.97, green: 0.56, blue: 0.11, alpha: 1)
    /// The flush the goose wears when a cursor invades its space.
    private static let angryFeather = NSColor(calibratedRed: 0.85, green: 0.19, blue: 0.15, alpha: 1)

    // MARK: - Body parts (drawn facing right, origin at the feet)

    private func draw(pose: Pose) {
        let feather = pose.angry ? Self.angryFeather : Self.feather
        drawShadow(bob: pose.bodyBob)
        // Back leg first, so the front one overlaps it.
        drawLeg(x: pose.legBack, bodyTop: 7 + pose.bodyBob)
        drawLeg(x: pose.legFront, bodyTop: 7 + pose.bodyBob)
        drawBody(bob: pose.bodyBob, feather: feather)
        drawHead(bob: pose.bodyBob, lead: pose.headLead, drop: pose.headDrop, angry: pose.angry, feather: feather)
    }

    /// A flat slab, not a gradient. Soft shadows belong to the smooth style; here
    /// a gradient would just look like a mistake.
    private func drawShadow(bob: CGFloat) {
        let inset = bob
        NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: -11 + inset, y: 0, width: 22 - inset * 2, height: 4)).fill()
    }

    private func drawLeg(x: CGFloat, bodyTop: CGFloat) {
        Self.bill.setFill()
        NSBezierPath(rect: NSRect(x: x, y: 2, width: 2, height: bodyTop - 2)).fill()
        NSBezierPath(rect: NSRect(x: x - 1, y: 1, width: 5, height: 2)).fill()
    }

    /// Two overlapping blobs plus a squared tail. The lopsided silhouette is the
    /// point — a single symmetrical oval reads as an egg, not a bird.
    private func drawBody(bob: CGFloat, feather: NSColor) {
        feather.setFill()

        NSBezierPath(ovalIn: NSRect(x: -14, y: 6 + bob, width: 26, height: 19)).fill()
        NSBezierPath(ovalIn: NSRect(x: -5, y: 11 + bob, width: 18, height: 16)).fill()
        NSBezierPath(rect: NSRect(x: -18, y: 13 + bob, width: 6, height: 5)).fill()
    }

    private func drawHead(bob: CGFloat, lead: CGFloat, drop: CGFloat, angry: Bool, feather: NSColor) {
        let x = 4 + lead
        let y = 21 + bob - drop

        feather.setFill()
        // A solid neck block, so head and body read as one mass rather than a ball
        // balanced on a stick.
        NSBezierPath(rect: NSRect(x: x + 1, y: y - 8, width: 8, height: 10)).fill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 13, height: 13)).fill()

        Self.bill.setFill()
        NSBezierPath(rect: NSRect(x: x + 11, y: y + 4, width: 6, height: 4)).fill()
        NSBezierPath(rect: NSRect(x: x + 16, y: y + 5, width: 2, height: 2)).fill()

        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: x + 7, y: y + 6, width: 2, height: 3)).fill()
        if angry {
            // A heavy brow slanting down toward the bill — the pixel-art shorthand for
            // rage. Each step drops one pixel as it nears the eye, forming a "\".
            NSBezierPath(rect: NSRect(x: x + 5, y: y + 12, width: 2, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: x + 6, y: y + 11, width: 2, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: x + 7, y: y + 10, width: 2, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: x + 8, y: y + 9, width: 2, height: 1)).fill()
        } else {
            // The brow. Four pixels of attitude, and the only reason this goose looks
            // annoyed rather than blank.
            NSBezierPath(rect: NSRect(x: x + 6, y: y + 10, width: 4, height: 1)).fill()
        }
    }
}
