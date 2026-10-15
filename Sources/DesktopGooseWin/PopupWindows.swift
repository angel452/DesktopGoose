import GoosePixels
import WinSDK

let bubbleClass = "DesktopGooseBubble"
let memeClass = "DesktopGooseMeme"

/// Routes clicks on a bubble back to the app, which closes it.
let bubbleProcedure: WNDPROC = { window, message, wParam, lParam in
    if message == wmMouseActivate { return maNoActivate }
    if message == wmLButtonDown, let window {
        app?.bubbleClicked(window)
        return 0
    }
    return DefWindowProcW(window, message, wParam, lParam)
}

/// Paints the meme and tells the app when the human closes it.
let memeProcedure: WNDPROC = { window, message, wParam, lParam in
    guard let window else { return DefWindowProcW(window, message, wParam, lParam) }
    switch message {
    case wmPaint:
        app?.paintMeme(window)
        return 0
    case wmWindowPosChanged:
        // Only a change of stacking matters; the goose's own drag moves the meme
        // with SWP_NOZORDER every tick.
        if let position = UnsafePointer<WINDOWPOS>(bitPattern: Int(lParam)),
           position.pointee.flags & swpNoZOrder == 0 {
            app?.memeRestacked()
        }
        // The default handler still sends WM_MOVE and WM_SIZE.
        return DefWindowProcW(window, message, wParam, lParam)
    case wmDestroy:
        app?.memeClosed(window)
        return 0
    default:
        return DefWindowProcW(window, message, wParam, lParam)
    }
}

/// A comic speech bubble rising out of the goose. Click it to dismiss it early;
/// otherwise it leaves on its own, or when the goose walks off.
final class SpeechBubbleWindow {
    static let lifetime = 12.0

    let window: HWND
    let bornAt: Double

    /// - Parameters:
    ///   - feetX, feetY: the goose's feet on the desktop.
    ///   - gooseHeight: how tall the goose stands, so the bubble clears its head.
    init?(
        text: String,
        font: BubbleFont,
        feetX: Int,
        feetY: Int,
        gooseHeight: Int,
        pixel: Int,
        displayScale: Double,
        now: Double
    ) {
        let textSize = font.measure(text)
        let size = BubbleShape.size(contentWidth: textSize.width, contentHeight: textSize.height, pixel: pixel)
        let placement = BubblePlacement(
            width: size.width,
            height: size.height,
            feetX: feetX,
            feetY: feetY,
            gooseHeight: gooseHeight,
            gap: Int((6 * displayScale).rounded()),
            pixel: pixel,
            workArea: workArea()
        )

        var canvas = PixelCanvas(width: size.width, height: size.height)
        BubbleShape.draw(on: &canvas, tailSide: placement.tailSide, tailCenterX: placement.tailCenterX, pixel: pixel)

        guard let surface = LayeredSurface(width: size.width, height: size.height),
              let window = createWindow(
                  className: bubbleClass,
                  title: "Desktop Goose",
                  style: wsPopup,
                  exStyle: wsExLayered | wsExTopmost | wsExToolWindow | wsExNoActivate,
                  x: Int32(placement.x), y: Int32(placement.y),
                  width: Int32(size.width), height: Int32(size.height)
              )
        else { return nil }

        surface.copy(canvas)
        let content = BubbleShape.contentRect(
            width: size.width,
            height: size.height,
            tailSide: placement.tailSide,
            pixel: pixel
        )
        font.draw(text, in: content, on: surface)

        self.window = window
        bornAt = now
        surface.present(to: window, x: placement.x, y: placement.y)
        ShowWindow(window, swShowNoActivate)
    }

    func close() {
        DestroyWindow(window)
    }
}

/// The bubble's typography: heavy, ink on white — the Mac's 15 pt heavy system font.
final class BubbleFont {
    private let font: HFONT
    private let measuringContext: HDC

    init?(displayScale: Double) {
        let height = -Int32((15 * displayScale).rounded())
        guard let font = CreateFontW(
            height, 0, 0, 0, fwExtraBold, 0, 0, 0,
            1, // DEFAULT_CHARSET
            0, 0, clearTypeQuality, 0,
            wide("Segoe UI")
        ), let context = CreateCompatibleDC(nil)
        else { return nil }

        self.font = font
        measuringContext = context
        SelectObject(context, font)
    }

    deinit {
        DeleteDC(measuringContext)
        DeleteObject(font)
    }

    func measure(_ text: String) -> (width: Int, height: Int) {
        var rect = RECT()
        var characters = wide(text)
        DrawTextW(measuringContext, &characters, -1, &rect, dtCalcRect | dtSingleLine | dtNoPrefix)
        return (Int(rect.right - rect.left), Int(rect.bottom - rect.top))
    }

    /// Draws centred text onto the bubble's pixels.
    ///
    /// GDI predates alpha and leaves the alpha byte of every pixel it touches at
    /// zero. The text area sits on opaque white paper, so it is simply made opaque
    /// again afterwards.
    func draw(_ text: String, in content: PixelRect, on surface: LayeredSurface) {
        let context = surface.deviceContext
        let previous = SelectObject(context, font)
        SetBkMode(context, transparentBackground)
        SetTextColor(context, COLORREF(0x001C_1C1C))

        var rect = RECT(
            left: LONG(content.x),
            top: LONG(content.y),
            right: LONG(content.maxX),
            bottom: LONG(content.maxY)
        )
        var characters = wide(text)
        DrawTextW(context, &characters, -1, &rect, dtCenter | dtVCenter | dtSingleLine | dtNoPrefix)
        GdiFlush()
        SelectObject(context, previous)

        for row in max(content.y, 0)..<min(content.maxY, surface.height) {
            for column in max(content.x, 0)..<min(content.maxX, surface.width) {
                surface.bits[row * surface.width + column] |= 0xFF00_0000
            }
        }
    }
}

/// The usable desktop, minus the taskbar.
func workArea() -> PixelRect {
    var rect = RECT()
    SystemParametersInfoW(spiGetWorkArea, 0, &rect, 0)
    return PixelRect(
        x: Int(rect.left),
        y: Int(rect.top),
        width: Int(rect.right - rect.left),
        height: Int(rect.bottom - rect.top)
    )
}

/// The meme the goose drags in — a real, titled window the human can move and
/// close. It stays open after the delivery; closing it is the human's call.
final class MemeWindow {
    let window: HWND
    private let image: PixelImage
    private var info = BITMAPINFO()
    /// The window's outer size, title bar included.
    let outerWidth: Int
    let outerHeight: Int

    init?(image source: PixelImage, title: String, displayScale: Double) {
        image = source.flattenedOnWhite()
        let fitted = MemePlacement.fitted(width: image.width, height: image.height, displayScale: displayScale)

        let style = wsPopup | wsCaption | wsSysMenu
        let exStyle = wsExTopmost | wsExToolWindow
        var frame = RECT(left: 0, top: 0, right: LONG(fitted.width), bottom: LONG(fitted.height))
        AdjustWindowRectEx(&frame, style, false, exStyle)
        outerWidth = Int(frame.right - frame.left)
        outerHeight = Int(frame.bottom - frame.top)

        guard let window = createWindow(
            className: memeClass,
            title: title,
            style: style,
            exStyle: exStyle,
            x: 0, y: 0,
            width: Int32(outerWidth), height: Int32(outerHeight)
        ) else { return nil }
        self.window = window

        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(image.width)
        info.bmiHeader.biHeight = -LONG(image.height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = biRGB
    }

    func show() {
        ShowWindow(window, swShowNoActivate)
    }

    func place(x: Int, y: Int) {
        move(window, x: x, y: y)
    }

    func close() {
        DestroyWindow(window)
    }

    /// Scales the meme into the client area with halftone filtering.
    func paint() {
        var paint = PAINTSTRUCT()
        guard let context = BeginPaint(window, &paint) else { return }
        defer { EndPaint(window, &paint) }

        var client = RECT()
        GetClientRect(window, &client)
        SetStretchBltMode(context, halftone)
        SetBrushOrgEx(context, 0, 0, nil)
        image.pixels.withUnsafeBufferPointer { pixels in
            _ = StretchDIBits(
                context,
                0, 0, client.right - client.left, client.bottom - client.top,
                0, 0, Int32(image.width), Int32(image.height),
                pixels.baseAddress, &info, dibRGBColors, srcCopy
            )
        }
    }
}
