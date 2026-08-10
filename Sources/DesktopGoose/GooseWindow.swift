import AppKit
import GooseArt
import GooseCore

/// A window just big enough to hold one animation frame, moved around the screen
/// to follow the goose.
///
/// The previous design painted the goose into a full-screen transparent overlay.
/// Measuring showed WindowServer paying ~29 points of CPU to recomposite a
/// screen-sized surface 60 times a second. Moving a small window instead is a
/// cheap WindowServer operation, and its contents only redraw when the animation
/// frame actually changes.
final class GooseWindow: NSWindow {
    private let gooseView: GooseView
    /// Where the goose's feet sit inside this window.
    private let feetOffset: CGPoint

    init(artwork: GooseArtwork) {
        // Mirroring flips the frame around the anchor, so the window is widened to
        // the larger of the two sides and the goose is centred on its feet.
        let halfWidth = max(artwork.anchor.x, artwork.frameSize.width - artwork.anchor.x)
        let size = NSSize(width: halfWidth * 2, height: artwork.frameSize.height)
        feetOffset = CGPoint(x: halfWidth, y: artwork.anchor.y)

        gooseView = GooseView(
            frame: NSRect(origin: .zero, size: size),
            artwork: artwork,
            feetOffset: feetOffset
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // One step above the mud, so footprints stay under the bird.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = gooseView
    }

    /// - Parameter screenPosition: the goose's feet, in screen coordinates.
    func update(
        screenPosition: CGPoint,
        facingLeft: Bool,
        visible: Bool,
        state: GooseState,
        deltaTime: TimeInterval
    ) {
        guard visible else {
            if isVisible { orderOut(nil) }
            return
        }

        // Snapped to whole points. The goose's position is a float, and landing a
        // pixel-art sprite on a fractional origin makes it resample every frame —
        // the sprite appears to vibrate instead of moving.
        setFrameOrigin(NSPoint(
            x: (screenPosition.x - feetOffset.x).rounded(),
            y: (screenPosition.y - feetOffset.y).rounded()
        ))
        gooseView.update(facingLeft: facingLeft, state: state, deltaTime: deltaTime)

        if !isVisible { orderFrontRegardless() }
    }
}

/// Draws a single animation frame, and only when that frame changes.
private final class GooseView: NSView {
    private let artwork: GooseArtwork
    private let feetOffset: CGPoint
    private var player: AnimationPlayer
    private var facingLeft = false

    init(frame frameRect: NSRect, artwork: GooseArtwork, feetOffset: CGPoint) {
        self.artwork = artwork
        self.feetOffset = feetOffset
        self.player = AnimationPlayer(clip: artwork.clipOrFallback(named: GooseClip.idle))
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(facingLeft: Bool, state: GooseState, deltaTime: TimeInterval) {
        let previousFrame = player.frame
        let wasFacingLeft = self.facingLeft

        self.facingLeft = facingLeft
        // Re-playing the running clip is a no-op, so this is safe every frame.
        player.play(artwork.clipOrFallback(named: GooseClip.name(for: state)))
        player.advance(by: deltaTime)

        // Walking moves the window, which costs nothing to redraw. Only a new frame
        // or a change of direction actually needs new pixels.
        if player.frame != previousFrame || facingLeft != wasFacingLeft {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        artwork.draw(frame: player.frame, at: feetOffset, facingLeft: facingLeft)
    }
}
