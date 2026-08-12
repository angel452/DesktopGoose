import AppKit

/// The meme the goose drags in during a reminder — a real, titled window the user
/// can move and close, not a click-through overlay.
///
/// The app drags it beside the goose while a delivery is in flight, then lets go.
/// It deliberately stays open afterwards: closing it is the user's call. It reports
/// its own close through `onClose` so the app can drop its reference.
final class MemeImageWindow: NSWindow {
    private var onClose: ((MemeImageWindow) -> Void)?
    private static let maximumEdge: CGFloat = 300

    init(image: NSImage, title: String, onClose: @escaping (MemeImageWindow) -> Void) {
        self.onClose = onClose
        let fitted = MemeImageWindow.fitted(image.size)

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: fitted))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        super.init(
            contentRect: NSRect(origin: .zero, size: fitted),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = title
        isReleasedWhenClosed = false
        // Above the desktop clutter while it is being shown; the goose itself sits
        // one level higher, so the pair reads correctly where they meet.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = imageView
    }

    /// Fires on every close path — the red button, Cmd+W, or `close()` — so the app
    /// can forget this window.
    override func close() {
        super.close()
        onClose?(self)
        onClose = nil
    }

    /// Places the meme beside the goose, on the trailing side, sitting on the same
    /// ground line so it reads as dragged rather than floating.
    ///
    /// - Parameter gooseHalfWidth: half the goose's on-screen width, so the gap is
    ///   measured from the goose's edge and the two never overlap.
    func place(besideFeet feet: CGPoint, onLeft: Bool, gooseHalfWidth: CGFloat, gap: CGFloat) {
        let clearance = gooseHalfWidth + gap
        let x = onLeft ? feet.x - clearance - frame.width : feet.x + clearance
        setFrameOrigin(NSPoint(x: x.rounded(), y: feet.y.rounded()))
    }

    private static func fitted(_ size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 120, height: 120) }
        let scale = min(maximumEdge / size.width, maximumEdge / size.height, 1)
        return NSSize(width: size.width * scale, height: size.height * scale)
    }
}
