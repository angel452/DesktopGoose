import Foundation
import GooseCore
import GoosePixels
import WinSDK

/// The Windows adapter: feeds the brain time and the cursor, and performs what it
/// reports. Same shape as the Mac's `AppDelegate`, with Win32 in place of AppKit.
final class GooseApp {
    private var brain: GooseBrain<SystemRandomNumberGenerator>
    private let screen: ScreenMapping
    private let metrics: PixelMetrics
    private let goose: GooseOverlay
    private let mud: MudOverlay
    private let font: BubbleFont?
    private let sounds = SoundBank()
    private(set) var tray: TrayIcon?
    private let trayWindow: HWND
    private var lastTick: Double

    /// Reminder and taunt bubbles on screen; they leave with the goose.
    private var bubbles: [SpeechBubbleWindow] = []
    /// Meme windows left open on screen; the human closes them.
    private var memes: [MemeWindow] = []
    /// The meme being dragged in during a delivery, if any.
    private var draggingMeme: MemeWindow?
    /// Whether this delivery already went to the meme bank. Set even when no meme
    /// came back, so a delivery never opens a second one — after "Shoo the Memes",
    /// say — and a failed lookup is not retried sixty times a second.
    private var fetchedDeliveryMeme = false

    init?(trayWindow: HWND) {
        let dpi = GetDpiForSystem()
        let displayScale = dpi > 0 ? Double(dpi) / 96 : 1
        screen = ScreenMapping(
            originX: 0,
            originY: 0,
            pixelWidth: Int(GetSystemMetrics(smCxScreen)),
            pixelHeight: Int(GetSystemMetrics(smCyScreen)),
            displayScale: displayScale
        )

        guard let directory = AssetPaths.spritesDirectory, let sheet = SpriteSheet(directory: directory) else {
            MessageBoxW(
                nil,
                wide("Desktop Goose could not find its sprites. Keep the Assets folder next to DesktopGoose.exe."),
                wide("Desktop Goose"),
                0x10 // MB_ICONERROR
            )
            return nil
        }

        metrics = PixelMetrics(manifest: sheet.manifest, displayScale: displayScale)
        // Mud first: Windows stacks a newer always-on-top window above older ones,
        // and the prints must stay under the bird.
        guard let mud = MudOverlay(screen: screen, pixel: metrics.artPixel),
              let goose = GooseOverlay(sheet: sheet, metrics: metrics)
        else { return nil }

        self.goose = goose
        self.mud = mud
        self.trayWindow = trayWindow
        font = BubbleFont(displayScale: displayScale)

        // The brain thinks in logical points, y up, exactly as on the Mac.
        brain = GooseBrain(
            bounds: CGRect(x: 0, y: 0, width: screen.logicalWidth, height: screen.logicalHeight),
            rng: SystemRandomNumberGenerator()
        )
        lastTick = monotonicSeconds()

        let icon = sheet.manifest.clip(named: GooseClip.idle)?.frames.first.map { sheet.frame($0) }
        tray = TrayIcon(owner: trayWindow, image: icon)
        // ~60 Hz. The real elapsed time is measured each tick, so timer jitter never
        // changes how fast the goose walks.
        // The default 15.6 ms timer resolution would round 16 ms up to ~31 ms and
        // halve the frame rate; ask for 1 ms while the goose runs.
        timeBeginPeriod(1)
        SetTimer(trayWindow, tickTimerID, 16, nil)
    }

    // MARK: - Run loop

    func tick() {
        let now = monotonicSeconds()
        // Clamp the delta so waking from sleep doesn't teleport the goose.
        let deltaTime = min(now - lastTick, 0.1)
        lastTick = now

        // GetCursorPos fails while the workstation is locked or a secure desktop
        // such as UAC is up; the brain then forgets the cursor instead of chasing
        // where it last was.
        var cursor = POINT()
        if GetCursorPos(&cursor) {
            let local = screen.toBrain(x: Int(cursor.x), y: Int(cursor.y))
            brain.aimCursor(at: CGPoint(x: local.x, y: local.y))
        } else {
            brain.aimCursor(at: nil)
        }

        let events = brain.update(deltaTime: deltaTime)
        for event in events {
            handle(event, now: now)
        }

        let feet = screen.toScreen(x: Double(brain.position.x), y: Double(brain.position.y))
        goose.update(
            feetX: feet.x,
            feetY: feet.y,
            facingLeft: brain.facingLeft,
            visible: brain.isVisible,
            state: brain.state,
            deltaTime: deltaTime
        )
        updateCarriedMeme(feetX: feet.x, feetY: feet.y)

        mud.prune(now: now)
        expireBubbles(now: now)
    }

    private func handle(_ event: GooseEvent, now: Double) {
        switch event {
        case let .footprint(position, muddy):
            guard muddy else { return }
            let point = screen.toScreen(x: Double(position.x), y: Double(position.y))
            mud.addFootprint(x: point.x, y: point.y, facingLeft: brain.facingLeft, now: now)

        case .honk:
            sounds.honk()

        case let .pecked(position):
            presentBubble(GooseLines.onCatch.randomElement() ?? GooseLines.fallback, at: position, now: now)

        case let .gaveUpChase(position):
            presentBubble(GooseLines.onGiveUp.randomElement() ?? GooseLines.fallback, at: position, now: now)

        case let .showReminder(position):
            presentBubble(GooseLines.reminders.randomElement() ?? GooseLines.fallback, at: position, now: now)

        case .startedMoving:
            // The goose walks off and its bubble goes with it. Dragged memes stay.
            dismissBubbles()

        case .visibilityChanged:
            // The brain emits its own `.honk` when a return deserves one.
            break
        }
    }

    // MARK: - Bubbles

    private func presentBubble(_ text: String, at position: CGPoint, now: Double) {
        guard let font else { return }
        let feet = screen.toScreen(x: Double(position.x), y: Double(position.y))
        if let bubble = SpeechBubbleWindow(
            text: text,
            font: font,
            feetX: feet.x,
            feetY: feet.y,
            gooseHeight: metrics.gooseHeight,
            pixel: metrics.artPixel,
            displayScale: screen.displayScale,
            now: now
        ) {
            bubbles.append(bubble)
            goose.raise()
        }
        sounds.honk()
    }

    private func expireBubbles(now: Double) {
        let expired = bubbles.filter { now - $0.bornAt >= SpeechBubbleWindow.lifetime }
        guard !expired.isEmpty else { return }
        for bubble in expired { bubble.close() }
        bubbles.removeAll { now - $0.bornAt >= SpeechBubbleWindow.lifetime }
    }

    func bubbleClicked(_ window: HWND) {
        guard let index = bubbles.firstIndex(where: { $0.window == window }) else { return }
        bubbles.remove(at: index).close()
    }

    private func dismissBubbles() {
        let closing = bubbles
        bubbles.removeAll()
        for bubble in closing { bubble.close() }
    }

    // MARK: - Memes

    /// Opens a meme window when a delivery starts dragging one in and keeps it
    /// beside the goose. When the delivery ends it lets go but leaves it open.
    private func updateCarriedMeme(feetX: Int, feetY: Int) {
        let carrying = brain.state == .deliveringEntry || brain.state == .presenting
        guard carrying else {
            draggingMeme = nil
            fetchedDeliveryMeme = false
            return
        }

        if !fetchedDeliveryMeme {
            fetchedDeliveryMeme = true
            // No meme in the bank? The goose still delivers, just empty-handed.
            guard let url = AssetPaths.memeURLs().randomElement(),
                  let image = ImageDecoder.load(url),
                  let meme = MemeWindow(image: image, title: url.lastPathComponent, displayScale: screen.displayScale)
            else { return }
            memes.append(meme)
            draggingMeme = meme
            place(meme, feetX: feetX, feetY: feetY)
            meme.show()
            goose.raise()
            return
        }

        // Closed mid-delivery? It stays the delivery's meme — no second one pops up,
        // the same as on the Mac — there is just nothing left to drag.
        if let meme = draggingMeme, IsWindow(meme.window) {
            place(meme, feetX: feetX, feetY: feetY)
        }
    }

    private func place(_ meme: MemeWindow, feetX: Int, feetY: Int) {
        let origin = MemePlacement.origin(
            feetX: feetX,
            feetY: feetY,
            onLeft: brain.dragFromLeft,
            gooseHalfWidth: metrics.halfWidth,
            gap: screen.pixels(12),
            windowWidth: meme.outerWidth,
            windowHeight: meme.outerHeight
        )
        meme.place(x: origin.x, y: origin.y)
    }

    /// A meme the human clicks or drags jumps to the top of the always-on-top band;
    /// lift the goose back over it, as on the Mac.
    func memeRestacked() {
        goose.raise()
    }

    func paintMeme(_ window: HWND) {
        memes.first { $0.window == window }?.paint()
    }

    /// Fires on every close path — the X button, Alt+F4, or "Shoo the Memes".
    func memeClosed(_ window: HWND) {
        memes.removeAll { $0.window == window }
    }

    // MARK: - Tray

    var soundLevel: SoundLevel { sounds.level }

    func choose(_ level: SoundLevel) {
        sounds.level = level
        // A sample honk, so the human hears what they just picked.
        sounds.honk()
    }

    func perform(_ command: TrayCommand) {
        switch command {
        case .remindNow:
            brain.requestReminder()
        case .shooMemes:
            dismissBubbles()
            let closing = memes
            draggingMeme = nil
            for meme in closing { meme.close() }
            memes.removeAll()
        case .quit:
            KillTimer(trayWindow, tickTimerID)
            timeEndPeriod(1)
            tray?.remove()
            DestroyWindow(trayWindow)
        }
    }
}
