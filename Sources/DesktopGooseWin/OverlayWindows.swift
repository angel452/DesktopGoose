import GooseCore
import GoosePixels
import WinSDK

/// The class name every click-through overlay shares; it does nothing but defer to
/// the default handler.
let overlayClass = "DesktopGooseOverlay"

let overlayProcedure: WNDPROC = { window, message, wParam, lParam in
    // Never take focus away from whatever the human is doing.
    if message == wmMouseActivate { return maNoActivate }
    return DefWindowProcW(window, message, wParam, lParam)
}

/// Borderless, transparent, always on top, invisible to clicks and the taskbar.
private let overlayExStyle = wsExLayered | wsExTransparent | wsExTopmost | wsExToolWindow | wsExNoActivate

/// A window just big enough for one animation frame, moved to follow the goose.
///
/// Same split as the Mac, for the same reason: moving a small window is cheap,
/// repainting a screen-sized one sixty times a second is not. The pixels only change
/// when the animation frame or facing does.
final class GooseOverlay {
    private let window: HWND
    private let surface: LayeredSurface
    private var canvas: PixelCanvas
    private let sheet: SpriteSheet
    private let metrics: PixelMetrics
    private var player: AnimationPlayer
    private var drawnFrame = -1
    private var drawnFacingLeft = false
    private var shown = false
    private var lastOrigin: (x: Int, y: Int) = (.min, .min)

    init?(sheet: SpriteSheet, metrics: PixelMetrics) {
        guard let surface = LayeredSurface(width: metrics.windowWidth, height: metrics.windowHeight),
              let window = createWindow(
                  className: overlayClass,
                  title: "Desktop Goose",
                  style: wsPopup,
                  exStyle: overlayExStyle,
                  x: 0, y: 0,
                  width: Int32(metrics.windowWidth),
                  height: Int32(metrics.windowHeight)
              )
        else { return nil }

        self.window = window
        self.surface = surface
        self.sheet = sheet
        self.metrics = metrics
        canvas = PixelCanvas(width: metrics.windowWidth, height: metrics.windowHeight)
        player = AnimationPlayer(clip: sheet.clipOrFallback(named: GooseClip.idle))
    }

    /// - Parameters:
    ///   - feetX, feetY: the goose's feet on the desktop, in pixels.
    func update(feetX: Int, feetY: Int, facingLeft: Bool, visible: Bool, state: GooseState, deltaTime: Double) {
        guard visible else {
            if shown {
                ShowWindow(window, swHide)
                shown = false
            }
            return
        }

        // Re-playing the running clip is a no-op, so this is safe every frame.
        player.play(sheet.clipOrFallback(named: GooseClip.name(for: state)))
        player.advance(by: deltaTime)

        let feet = metrics.feetInWindow
        let origin = (x: feetX - feet.x, y: feetY - feet.y)

        if player.frame != drawnFrame || facingLeft != drawnFacingLeft || !shown {
            drawnFrame = player.frame
            drawnFacingLeft = facingLeft
            canvas.clear()
            let frameOrigin = metrics.frameOrigin(facingLeft: facingLeft)
            canvas.blit(
                sheet.frame(player.frame),
                x: frameOrigin.x,
                y: frameOrigin.y,
                scale: metrics.artPixel,
                mirrored: facingLeft
            )
            surface.copy(canvas)
            surface.present(to: window, x: origin.x, y: origin.y)
        } else if origin != lastOrigin {
            move(window, x: origin.x, y: origin.y)
        }
        lastOrigin = origin

        if !shown {
            ShowWindow(window, swShowNoActivate)
            shown = true
        }
    }

    /// Keeps the goose above windows that opened after it, such as a dragged meme.
    func raise() {
        raiseToTop(window)
    }
}

/// A screen-sized click-through window holding nothing but footprints. It repaints
/// only when a print lands or fades.
final class MudOverlay {
    private let window: HWND
    private let surface: LayeredSurface
    private var canvas: PixelCanvas
    private var trail = FootprintTrail()
    private let screen: ScreenMapping
    private let pixel: Int
    private var lastPrune = 0.0

    init?(screen: ScreenMapping, pixel: Int) {
        guard let surface = LayeredSurface(width: screen.pixelWidth, height: screen.pixelHeight),
              let window = createWindow(
                  className: overlayClass,
                  title: "Desktop Goose Mud",
                  style: wsPopup,
                  exStyle: overlayExStyle,
                  x: Int32(screen.originX), y: Int32(screen.originY),
                  width: Int32(screen.pixelWidth),
                  height: Int32(screen.pixelHeight)
              )
        else { return nil }

        self.window = window
        self.surface = surface
        self.screen = screen
        self.pixel = pixel
        canvas = PixelCanvas(width: screen.pixelWidth, height: screen.pixelHeight)
        repaint()
        ShowWindow(window, swShowNoActivate)
    }

    func addFootprint(x: Int, y: Int, facingLeft: Bool, now: Double) {
        trail.add(x: x, y: y, facingLeft: facingLeft, now: now)
        repaint()
    }

    /// Drops expired prints a couple of times a second, repainting only when one went.
    func prune(now: Double) {
        guard now - lastPrune >= 0.5 else { return }
        lastPrune = now
        if trail.prune(now: now) { repaint() }
    }

    private func repaint() {
        canvas.clear()
        trail.draw(on: &canvas, originX: screen.originX, originY: screen.originY, pixel: pixel)
        surface.copy(canvas)
        surface.present(to: window, x: screen.originX, y: screen.originY)
    }
}
