import AppKit
import GooseArt

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
    }

    private var footprints: [Footprint] = []
    private var nextFootIsLeft = true
    private let footprintLimit = 800
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
        footprints.append(Footprint(position: position, facingLeft: facingLeft, isLeftFoot: nextFootIsLeft))
        nextFootIsLeft.toggle()

        if footprints.count > footprintLimit {
            let dropped = footprints.removeFirst()
            setNeedsDisplay(footprintRect(around: dropped.position))
        }
        setNeedsDisplay(footprintRect(around: position))
    }

    func clear() {
        guard !footprints.isEmpty else { return }
        footprints.removeAll()
        needsDisplay = true
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
