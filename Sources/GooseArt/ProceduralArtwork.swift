import AppKit
import GooseCore

/// Draws the goose with vector paths, so the app runs before any artwork exists.
///
/// It also doubles as the source for `SpriteSheetBaker`: every frame it can draw
/// is a frame that can be baked into a real sheet.
public struct ProceduralArtwork: GooseArtwork {
    public static let walkFrameCount = 12
    public static let idleFrameCount = 4

    public var frameCount: Int { Self.walkFrameCount + Self.idleFrameCount }

    /// Generous enough to hold the bill, the tail, the widest leg swing and the
    /// contact shadow.
    public var frameSize: CGSize { CGSize(width: 120, height: 116) }
    public var anchor: CGPoint { CGPoint(x: 52, y: 5) }

    public init() {}

    public func clip(named name: String) -> AnimationClip? {
        switch name {
        case GooseClip.walk:
            return AnimationClip(
                name: GooseClip.walk,
                frames: Array(0..<Self.walkFrameCount),
                framesPerSecond: 14
            )
        case GooseClip.idle:
            return AnimationClip(
                name: GooseClip.idle,
                frames: Array(Self.walkFrameCount..<(Self.walkFrameCount + Self.idleFrameCount)),
                framesPerSecond: 4
            )
        // The vector fallback has no angry pose; it reuses the plain motion so the
        // charge still animates when no baked sheet is present.
        case GooseClip.angryWalk:
            return AnimationClip(
                name: GooseClip.angryWalk,
                frames: Array(0..<Self.walkFrameCount),
                framesPerSecond: 14
            )
        case GooseClip.angryIdle:
            return AnimationClip(
                name: GooseClip.angryIdle,
                frames: Array(Self.walkFrameCount..<(Self.walkFrameCount + Self.idleFrameCount)),
                framesPerSecond: 4
            )
        default:
            return nil
        }
    }

    public func draw(frame: Int, at point: CGPoint, facingLeft: Bool) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        if facingLeft { transform.scaleX(by: -1, yBy: 1) }
        transform.concat()

        draw(pose: Pose(frame: frame))
    }

    // MARK: - Pose

    /// The frame index turned into joint offsets.
    ///
    /// A goose does not just swing its legs. Its body rises and falls twice per
    /// stride — once per footfall — and its head thrusts forward and back. That
    /// head bob is the single most recognisable thing about how these birds walk.
    private struct Pose {
        let legSwing: CGFloat
        /// Vertical body movement. Rises on each footfall.
        let bodyBob: CGFloat
        /// Horizontal head thrust, the goose's signature.
        let headLead: CGFloat
        /// Vertical head movement, counter to the body so the head stays steadier.
        let headLift: CGFloat

        init(frame: Int) {
            if frame < ProceduralArtwork.walkFrameCount {
                let phase = CGFloat(frame) / CGFloat(ProceduralArtwork.walkFrameCount) * .pi * 2
                legSwing = sin(phase) * 9
                bodyBob = abs(sin(phase * 2)) * 2.5
                headLead = sin(phase) * 6
                headLift = -abs(sin(phase * 2)) * 1.8
            } else {
                // Idling only breathes.
                let idleFrame = frame - ProceduralArtwork.walkFrameCount
                let phase = CGFloat(idleFrame) / CGFloat(ProceduralArtwork.idleFrameCount) * .pi * 2
                legSwing = 0
                bodyBob = sin(phase) * 1.5
                headLead = sin(phase) * 1.5
                headLift = sin(phase) * 1
            }
        }
    }

    // MARK: - Palette

    private static let feather = NSColor(calibratedWhite: 0.98, alpha: 1)
    private static let featherShade = NSColor(calibratedWhite: 0.93, alpha: 1)
    private static let outline = NSColor(calibratedWhite: 0.55, alpha: 1)
    private static let beak = NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.13, alpha: 1)

    // MARK: - Body parts (drawn facing right, origin at the feet)

    /// Draw order is the whole trick: the shadow goes underneath everything, the
    /// neck before the body so the body covers where it joins, and the wing after
    /// the body so it sits on top of it.
    private func draw(pose: Pose) {
        drawShadow(bob: pose.bodyBob)
        drawLeg(offsetX: -6, swing: pose.legSwing, bodyBottom: 26 + pose.bodyBob)
        drawLeg(offsetX: 8, swing: -pose.legSwing, bodyBottom: 26 + pose.bodyBob)
        drawNeck(bob: pose.bodyBob, lead: pose.headLead, lift: pose.headLift)
        drawBody(bob: pose.bodyBob)
        drawWing(bob: pose.bodyBob)
        drawHead(bob: pose.bodyBob, lead: pose.headLead, lift: pose.headLift)
    }

    /// A soft contact shadow. Without it the goose reads as pasted on top of the
    /// screen rather than standing on it — and it shrinks as the body lifts, which
    /// is what sells the bob as weight rather than jitter.
    private func drawShadow(bob: CGFloat) {
        let spread = 1 - bob / 14
        let width = 60 * spread
        let height = 13 * spread

        let rect = NSRect(x: -width / 2 + 2, y: 3 - height / 2, width: width, height: height)
        guard let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.26),
            NSColor(calibratedWhite: 0, alpha: 0),
        ]) else { return }

        gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
    }

    private func drawLeg(offsetX: CGFloat, swing: CGFloat, bodyBottom: CGFloat) {
        Self.beak.setStroke()
        let leg = NSBezierPath()
        leg.move(to: CGPoint(x: offsetX, y: bodyBottom))
        leg.line(to: CGPoint(x: offsetX + swing, y: 4))
        leg.lineWidth = 4
        leg.lineCapStyle = .round
        leg.stroke()

        Self.beak.setFill()
        NSBezierPath(ovalIn: NSRect(x: offsetX + swing - 7, y: 1, width: 16, height: 5)).fill()
    }

    /// An S-curve, not a tube. The neck leans back out of the body and then sweeps
    /// forward to the head, and it tapers on the way up.
    private func drawNeck(bob: CGFloat, lead: CGFloat, lift: CGFloat) {
        let base = CGPoint(x: 0, y: 38 + bob)
        let middle = CGPoint(x: 8 + lead * 0.3, y: 72 + bob)
        let top = CGPoint(x: 26 + lead, y: 92 + bob + lift)

        let lower = NSBezierPath()
        lower.move(to: base)
        lower.curve(
            to: middle,
            controlPoint1: CGPoint(x: -5, y: 52 + bob),
            controlPoint2: CGPoint(x: 0, y: 64 + bob)
        )

        let upper = NSBezierPath()
        upper.move(to: middle)
        upper.curve(
            to: top,
            controlPoint1: CGPoint(x: 15 + lead * 0.6, y: 80 + bob),
            controlPoint2: CGPoint(x: 22 + lead, y: 86 + bob)
        )

        for path in [lower, upper] { path.lineCapStyle = .round }

        // Stroked twice: a wider dark pass shows through as the outline, then the
        // feather colour fills the middle. The upper segment is thinner, which is
        // what makes the neck taper.
        Self.outline.setStroke()
        lower.lineWidth = 19
        lower.stroke()
        upper.lineWidth = 15
        upper.stroke()

        Self.feather.setStroke()
        lower.lineWidth = 16
        lower.stroke()
        upper.lineWidth = 12
        upper.stroke()
    }

    private func drawBody(bob: CGFloat) {
        let body = NSBezierPath(ovalIn: NSRect(x: -36, y: 20 + bob, width: 68, height: 44))
        Self.feather.setFill()
        body.fill()

        // A flat, wide tail rather than a spike.
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: -28, y: 54 + bob))
        tail.curve(
            to: CGPoint(x: -52, y: 50 + bob),
            controlPoint1: CGPoint(x: -38, y: 58 + bob),
            controlPoint2: CGPoint(x: -46, y: 56 + bob)
        )
        tail.curve(
            to: CGPoint(x: -28, y: 36 + bob),
            controlPoint1: CGPoint(x: -44, y: 44 + bob),
            controlPoint2: CGPoint(x: -36, y: 38 + bob)
        )
        tail.close()
        Self.feather.setFill()
        tail.fill()
        Self.outline.setStroke()
        tail.lineWidth = 1.5
        tail.stroke()

        // Drawn last so the body's own edge stays on top of the tail's.
        Self.outline.setStroke()
        body.lineWidth = 1.5
        body.stroke()
    }

    /// The single biggest change to how the goose reads. A blank oval is a blob;
    /// an oval with a folded wing on it is a bird.
    private func drawWing(bob: CGFloat) {
        let wing = NSBezierPath()
        wing.move(to: CGPoint(x: -24, y: 46 + bob))
        wing.curve(
            to: CGPoint(x: 16, y: 38 + bob),
            controlPoint1: CGPoint(x: -14, y: 58 + bob),
            controlPoint2: CGPoint(x: 8, y: 52 + bob)
        )
        wing.curve(
            to: CGPoint(x: -24, y: 46 + bob),
            controlPoint1: CGPoint(x: 2, y: 30 + bob),
            controlPoint2: CGPoint(x: -16, y: 34 + bob)
        )
        wing.close()

        Self.featherShade.setFill()
        wing.fill()
        Self.outline.setStroke()
        wing.lineWidth = 1.5
        wing.stroke()

        // One feather crease, enough to suggest the fold without drawing plumage.
        let crease = NSBezierPath()
        crease.move(to: CGPoint(x: -16, y: 42 + bob))
        crease.curve(
            to: CGPoint(x: 10, y: 40 + bob),
            controlPoint1: CGPoint(x: -6, y: 47 + bob),
            controlPoint2: CGPoint(x: 3, y: 45 + bob)
        )
        crease.lineWidth = 1.2
        Self.outline.setStroke()
        crease.stroke()
    }

    private func drawHead(bob: CGFloat, lead: CGFloat, lift: CGFloat) {
        let x = 16 + lead
        let y = 84 + bob + lift

        let head = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 25, height: 23))
        Self.feather.setFill()
        head.fill()
        Self.outline.setStroke()
        head.lineWidth = 1.5
        head.stroke()

        let bill = NSBezierPath()
        bill.move(to: CGPoint(x: x + 21, y: y + 15))
        bill.curve(
            to: CGPoint(x: x + 40, y: y + 9),
            controlPoint1: CGPoint(x: x + 30, y: y + 15),
            controlPoint2: CGPoint(x: x + 37, y: y + 12)
        )
        bill.curve(
            to: CGPoint(x: x + 21, y: y + 5),
            controlPoint1: CGPoint(x: x + 36, y: y + 6),
            controlPoint2: CGPoint(x: x + 30, y: y + 5)
        )
        bill.close()
        Self.beak.setFill()
        bill.fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: x + 13, y: y + 13, width: 4.5, height: 4.5)).fill()
    }
}
