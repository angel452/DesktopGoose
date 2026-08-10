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
    private var openMemes: [MemeWindow] = []
    private let sounds = SoundBank()
    /// Kept so speech bubbles can match the goose's medium and clear its head.
    private var artStyle: ArtStyle?
    private var gooseHeight: CGFloat = 0

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
    }

    private func handle(_ event: GooseEvent, facingLeft: Bool) {
        switch event {
        case let .footprint(position, muddy):
            guard muddy else { return }
            mudWindow?.mudView.addFootprint(at: position, facingLeft: facingLeft)

        case .honk:
            sounds.honk()

        case let .droppedMeme(position):
            dropMeme(at: position)

        case .startedMoving:
            // The goose walks off, the bubble goes with it. Leaving it hanging over
            // an empty patch of desktop is what makes these things feel like litter.
            dismissMemes()

        case let .visibilityChanged(isVisible):
            // Announce the return trip. Something is different about those feet.
            if isVisible { sounds.honk() }
        }
    }

    private func screenPoint(from local: CGPoint) -> CGPoint {
        CGPoint(x: screenOrigin.x + local.x, y: screenOrigin.y + local.y)
    }

    private func dropMeme(at localPoint: CGPoint) {
        guard let artStyle else { return }

        let meme = MemeWindow(
            image: Assets.randomMeme(),
            style: artStyle,
            gooseFeet: screenPoint(from: localPoint),
            gooseHeight: gooseHeight
        )
        meme.present { [weak self] closed in
            self?.openMemes.removeAll { $0 === closed }
        }
        openMemes.append(meme)
    }

    // MARK: - Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🪿"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Clean the Screen", action: #selector(cleanScreen), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Shoo the Memes", action: #selector(dismissMemes), keyEquivalent: "m"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Goose", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func cleanScreen() {
        mudWindow?.mudView.clear()
    }

    @objc private func dismissMemes() {
        for meme in openMemes { meme.close() }
        openMemes.removeAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
