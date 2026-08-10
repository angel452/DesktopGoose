import AppKit
import GooseArt

/// A comic speech bubble rising out of the goose, holding whatever it just dragged
/// in. Click it to make it go away; otherwise it leaves on its own.
final class MemeWindow: NSWindow {
    private var dismissTimer: Timer?
    private var onClose: ((MemeWindow) -> Void)?

    private static let maximumEdge: CGFloat = 260
    private static let lifetime: TimeInterval = 12
    /// Gap between the goose's head and the tip of the tail.
    private static let gap: CGFloat = 6

    /// - Parameters:
    ///   - gooseFeet: the goose's feet, in screen coordinates.
    ///   - gooseHeight: how tall the goose stands, so the bubble clears its head.
    init(image: NSImage?, style: ArtStyle, gooseFeet: CGPoint, gooseHeight: CGFloat) {
        let content = MemeWindow.fittedSize(for: image)
        let size = SpeechBubble.size(forContent: content, style: style)

        let visible = NSScreen.screens.first { $0.frame.contains(gooseFeet) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Speak upwards. If the goose is too near the top of the screen there is no
        // room, so the bubble drops below it and the tail flips over.
        let headY = gooseFeet.y + gooseHeight + MemeWindow.gap
        let fitsAbove = headY + size.height <= visible.maxY
        let tailSide: SpeechBubble.TailSide = fitsAbove ? .bottom : .top
        let originY = fitsAbove ? headY : gooseFeet.y - size.height - MemeWindow.gap

        let originX = min(max(gooseFeet.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let origin = CGPoint(x: originX.rounded(), y: originY.rounded())

        // The tail keeps pointing at the goose even when the bubble has been pushed
        // sideways to stay on screen.
        let range = SpeechBubble.tailRange(in: size.width, style: style)
        let tailCenterX = min(max(gooseFeet.x - origin.x, range.lowerBound), range.upperBound)

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // The bubble draws its own hard border; a soft system shadow would fight it.
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        contentView = BubbleContentView(
            image: image,
            style: style,
            tailSide: tailSide,
            tailCenterX: tailCenterX
        ) { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    func present(onClose: @escaping (MemeWindow) -> Void) {
        self.onClose = onClose
        orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(withTimeInterval: MemeWindow.lifetime, repeats: false) { [weak self] _ in
            self?.close()
        }
    }

    override func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        super.close()
        onClose?(self)
        onClose = nil
    }

    private static func fittedSize(for image: NSImage?) -> NSSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            // Measured, not guessed. A hardcoded width clipped the exclamation mark
            // the moment the font size changed.
            let text = SpeechBubble.placeholderText().size()
            return NSSize(width: ceil(text.width), height: ceil(text.height))
        }

        let scale = min(maximumEdge / image.size.width, maximumEdge / image.size.height, 1)
        return NSSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

/// Draws the bubble, then the meme — or the stand-in line when `Assets/Memes` is
/// still empty.
private final class BubbleContentView: NSView {
    private let image: NSImage?
    private let style: ArtStyle
    private let tailSide: SpeechBubble.TailSide
    private let tailCenterX: CGFloat
    private let onClick: () -> Void

    init(
        image: NSImage?,
        style: ArtStyle,
        tailSide: SpeechBubble.TailSide,
        tailCenterX: CGFloat,
        onClick: @escaping () -> Void
    ) {
        self.image = image
        self.style = style
        self.tailSide = tailSide
        self.tailCenterX = tailCenterX
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        SpeechBubble.draw(in: bounds, tailSide: tailSide, tailCenterX: tailCenterX, style: style)

        let content = SpeechBubble.contentRect(in: bounds, tailSide: tailSide, style: style)

        if let image {
            image.draw(in: content)
            return
        }

        let text = SpeechBubble.placeholderText()
        // Centred by hand: draw(in:) lays out from the top of the rect down.
        let height = text.size().height
        text.draw(in: NSRect(
            x: content.minX,
            y: content.midY - height / 2,
            width: content.width,
            height: height + 1
        ))
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
