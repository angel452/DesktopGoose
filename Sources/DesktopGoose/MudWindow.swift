import AppKit
import GooseArt
import QuartzCore

/// A full-screen transparent window holding nothing but footprints.
///
/// It stays screen-sized because mud has to persist wherever the goose has been,
/// but it repaints only when a footprint lands — a couple of times a second while
/// walking, and never at all otherwise.
final class MudWindow: NSWindow {
    let mudView: MudView

    init(screenFrame: NSRect, artwork: any GooseArtwork) {
        mudView = MudView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            style: ArtStyle(artwork: artwork)
        )

        super.init(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Clicks land on whatever is underneath, never on the mud.
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = mudView
    }
}

final class MudView: NSView {
    private struct Footprint {
        let position: CGPoint
        let facingLeft: Bool
        let isLeftFoot: Bool
        /// When the print landed, on the media clock, so it can expire on its own.
        let bornAt: CFTimeInterval
    }

    private var footprints: [Footprint] = []
    private var nextFootIsLeft = true
    private let footprintLimit = 800
    /// How long a footprint lingers before it fades from the screen, in seconds.
    private let footprintLifetime: CFTimeInterval = 10
    /// Prunes expired prints. Runs only while prints exist; stops when none do.
    private var pruneTimer: Timer?
    private let style: ArtStyle

    init(frame frameRect: NSRect, style: ArtStyle) {
        self.style = style
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func addFootprint(at position: CGPoint, facingLeft: Bool) {
        footprints.append(Footprint(
            position: position,
            facingLeft: facingLeft,
            isLeftFoot: nextFootIsLeft,
            bornAt: CACurrentMediaTime()
        ))
        nextFootIsLeft.toggle()

        if footprints.count > footprintLimit {
            let dropped = footprints.removeFirst()
            setNeedsDisplay(footprintRect(around: dropped.position))
        }
        setNeedsDisplay(footprintRect(around: position))
        startPruning()
    }

    // MARK: - Expiry

    /// Wakes a couple of times a second while prints exist to drop the ones past
    /// their lifetime. Between removals it does nothing but a comparison — a print
    /// only ever forces a repaint of the small patch it vacated, never the screen.
    private func startPruning() {
        guard pruneTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.prune()
        }
        // .common so pruning keeps up while a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    private func stopPruning() {
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    private func prune() {
        let now = CACurrentMediaTime()
        // Prints are appended in time order, so the expired ones are always at the
        // front. Drop them and repaint only the patches they leave behind.
        while let oldest = footprints.first, now - oldest.bornAt >= footprintLifetime {
            footprints.removeFirst()
            setNeedsDisplay(footprintRect(around: oldest.position))
        }
        if footprints.isEmpty { stopPruning() }
    }

    deinit {
        pruneTimer?.invalidate()
    }

    override func draw(_ dirtyRect: NSRect) {
        for footprint in footprints where footprintRect(around: footprint.position).intersects(dirtyRect) {
            MudRenderer.drawFootprint(
                at: footprint.position,
                facingLeft: footprint.facingLeft,
                isLeftFoot: footprint.isLeftFoot,
                style: style
            )
        }
    }

    private func footprintRect(around point: CGPoint) -> NSRect {
        NSRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
    }
}
