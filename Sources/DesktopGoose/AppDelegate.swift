import AppKit
import GooseArt
import GooseCore
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mudWindow: MudWindow?
    private var gooseWindow: GooseWindow?
    private var brain: GooseBrain<SystemRandomNumberGenerator>?
    private var ticker: Timer?
    private var statusItem: NSStatusItem?
    private var lastTick: CFTimeInterval = 0
    /// Bottom-left of the screen the goose lives on, in global desktop coordinates.
    private var screenOrigin: CGPoint = .zero
    /// Reminder message bubbles currently on screen; they leave with the goose.
    private var openBubbles: [MessageBubble] = []
    /// Meme windows dragged in and left open on screen; the user closes them.
    private var memeImages: [MemeImageWindow] = []
    /// The meme currently being dragged in during a delivery, if any.
    private var draggingMeme: MemeImageWindow?
    private let sounds = SoundBank()
    /// Kept so speech bubbles can match the goose's medium and clear its head.
    private var artStyle: ArtStyle?
    private var gooseHeight: CGFloat = 0
    /// Half the goose's on-screen width, so a dragged meme can clear its side.
    private var gooseHalfWidth: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        screenOrigin = screen.frame.origin

        // A real sprite sheet if one is installed, hand-drawn vectors otherwise.
        // The app never fails to draw a goose because an asset is missing.
        //
        // Both look the same on screen — the baked sheet is a render of the vector
        // goose — so which one loaded is announced rather than left to guesswork.
        let artwork: GooseArtwork
        if let sheet = SpriteSheetArtwork(directory: Assets.spritesDirectory) {
            artwork = sheet
            print("artwork: sprite sheet — \(Assets.spritesDirectory?.path ?? "unknown path")")
        } else {
            artwork = ProceduralArtwork()
            print("artwork: procedural fallback — no usable sheet found")
        }

        artStyle = ArtStyle(artwork: artwork)
        gooseHeight = artwork.frameSize.height - artwork.anchor.y
        gooseHalfWidth = max(artwork.anchor.x, artwork.frameSize.width - artwork.anchor.x)

        // Two windows, deliberately. The mud is screen-sized but almost never
        // repaints; the goose repaints often but is the size of one frame.
        let mud = MudWindow(screenFrame: screen.frame, artwork: artwork)
        mud.orderFrontRegardless()
        mudWindow = mud

        gooseWindow = GooseWindow(artwork: artwork)

        // The brain thinks in screen-local coordinates, so it never has to know
        // where this screen sits in the global desktop arrangement.
        brain = GooseBrain(
            bounds: CGRect(origin: .zero, size: screen.frame.size),
            rng: SystemRandomNumberGenerator()
        )

        installStatusItem()
        startTicking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate()
    }

    // MARK: - Run loop

    private func startTicking() {
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps the goose moving while menus are open or windows are dragged.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard var brain else { return }

        let now = CACurrentMediaTime()
        // Clamp the delta so waking from sleep doesn't teleport the goose.
        let deltaTime = min(now - lastTick, 0.1)
        lastTick = now

        // Hand the goose the cursor in its own screen-local coordinates.
        let cursor = NSEvent.mouseLocation
        brain.aimCursor(at: CGPoint(x: cursor.x - screenOrigin.x, y: cursor.y - screenOrigin.y))

        let events = brain.update(deltaTime: deltaTime)
        self.brain = brain

        for event in events {
            handle(event, facingLeft: brain.facingLeft)
        }

        gooseWindow?.update(
            screenPosition: screenPoint(from: brain.position),
            facingLeft: brain.facingLeft,
            visible: brain.isVisible,
            state: brain.state,
            deltaTime: deltaTime
        )

        updateCarriedMeme(
            state: brain.state,
            feet: screenPoint(from: brain.position),
            onLeft: brain.dragFromLeft
        )
    }

    /// Opens a meme window when a delivery starts dragging one in and keeps it
    /// beside the goose. When the delivery ends it lets go but leaves the window
    /// open — closing it is the user's call.
    private func updateCarriedMeme(state: GooseState, feet: CGPoint, onLeft: Bool) {
        let carrying = state == .deliveringEntry || state == .presenting
        guard carrying else {
            draggingMeme = nil
            return
        }

        if draggingMeme == nil {
            // No meme in the bank? The goose still delivers the message, just
            // empty-handed.
            guard let url = Assets.randomMemeURL(), let image = NSImage(contentsOf: url) else { return }
            let window = MemeImageWindow(image: image, title: url.lastPathComponent) { [weak self] closed in
                self?.memeImages.removeAll { $0 === closed }
            }
            window.orderFrontRegardless()
            memeImages.append(window)
            draggingMeme = window
        }

        draggingMeme?.place(besideFeet: feet, onLeft: onLeft, gooseHalfWidth: gooseHalfWidth, gap: 12)
    }

    private func handle(_ event: GooseEvent, facingLeft: Bool) {
        switch event {
        case let .footprint(position, muddy):
            guard muddy else { return }
            mudWindow?.mudView.addFootprint(at: position, facingLeft: facingLeft)

        case .honk:
            sounds.honk()

        case .pecked:
            // The satisfying "gotcha" — same honk for now; a sharper peck sound
            // and a jab animation are a later polish.
            sounds.honk()

        case let .showReminder(position):
            presentReminder(at: position)

        case .startedMoving:
            // The goose walks off, its message bubble goes with it. The dragged meme
            // window stays put — closing that one is the user's call.
            dismissBubbles()

        case .visibilityChanged:
            // The brain now decides whether a return is worth a honk and emits it
            // as a `.honk` event, so there is nothing to announce here.
            break
        }
    }

    private func screenPoint(from local: CGPoint) -> CGPoint {
        CGPoint(x: screenOrigin.x + local.x, y: screenOrigin.y + local.y)
    }

    private func presentReminder(at localPoint: CGPoint) {
        guard let artStyle else { return }

        let bubble = MessageBubble(
            message: ReminderMessages.attributed(),
            style: artStyle,
            gooseFeet: screenPoint(from: localPoint),
            gooseHeight: gooseHeight
        )
        bubble.present { [weak self] closed in
            self?.openBubbles.removeAll { $0 === closed }
        }
        openBubbles.append(bubble)
        sounds.honk()
    }

    // MARK: - Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🪿"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Take a Break Now", action: #selector(remindNow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Shoo the Memes", action: #selector(dismissMemes), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Goose", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func remindNow() {
        brain?.requestReminder()
    }

    /// Closes only the message bubbles — used when the goose sets off, so the meme
    /// windows it left open are untouched.
    private func dismissBubbles() {
        for bubble in openBubbles { bubble.close() }
        openBubbles.removeAll()
    }

    @objc private func dismissMemes() {
        dismissBubbles()
        for image in memeImages { image.close() }
        memeImages.removeAll()
        draggingMeme = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
