import AppKit
import GooseArt

/// A comic speech bubble rising out of the goose to show a reminder message.
/// Click it to dismiss it early; otherwise it leaves on its own, or when the goose
/// walks off.
final class MessageBubble: NSWindow {
    private var dismissTimer: Timer?
    private var onClose: ((MessageBubble) -> Void)?

    private static let lifetime: TimeInterval = 12
    /// Gap between the goose's head and the tip of the tail.
    private static let gap: CGFloat = 6

    /// - Parameters:
    ///   - gooseFeet: the goose's feet, in screen coordinates.
    ///   - gooseHeight: how tall the goose stands, so the bubble clears its head.
    init(message: NSAttributedString, style: ArtStyle, gooseFeet: CGPoint, gooseHeight: CGFloat) {
        let text = message.size()
        let content = NSSize(width: ceil(text.width), height: ceil(text.height))
        let size = SpeechBubble.size(forContent: content, style: style)

        let visible = NSScreen.screens.first { $0.frame.contains(gooseFeet) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Speak upwards. If the goose is too near the top of the screen there is no
        // room, so the bubble drops below it and the tail flips over.
        let headY = gooseFeet.y + gooseHeight + MessageBubble.gap
        let fitsAbove = headY + size.height <= visible.maxY
        let tailSide: SpeechBubble.TailSide = fitsAbove ? .bottom : .top
        let originY = fitsAbove ? headY : gooseFeet.y - size.height - MessageBubble.gap

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
            message: message,
            style: style,
            tailSide: tailSide,
            tailCenterX: tailCenterX
        ) { [weak self] in self?.close() }
    }

    override var canBecomeKey: Bool { true }

    func present(onClose: @escaping (MessageBubble) -> Void) {
        self.onClose = onClose
        orderFrontRegardless()

        dismissTimer = Timer.scheduledTimer(withTimeInterval: MessageBubble.lifetime, repeats: false) { [weak self] _ in
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
}

/// Draws the bubble and centres the reminder line inside it.
private final class BubbleContentView: NSView {
    private let message: NSAttributedString
    private let style: ArtStyle
    private let tailSide: SpeechBubble.TailSide
    private let tailCenterX: CGFloat
    private let onClick: () -> Void

    init(
        message: NSAttributedString,
        style: ArtStyle,
        tailSide: SpeechBubble.TailSide,
        tailCenterX: CGFloat,
        onClick: @escaping () -> Void
    ) {
        self.message = message
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
        // Centred by hand: draw(in:) lays out from the top of the rect down.
        let height = message.size().height
        message.draw(in: NSRect(
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
