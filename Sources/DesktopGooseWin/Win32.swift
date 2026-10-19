import GoosePixels
import WinSDK

// Win32 constants spelled out as typed values. Many Windows macros either do not
// import into Swift (they contain casts) or import with a type that never matches
// the parameter, so the handful this app needs live here, checked against the SDK
// headers.

let wsPopup: DWORD = 0x8000_0000
let wsCaption: DWORD = 0x00C0_0000
let wsSysMenu: DWORD = 0x0008_0000

let wsExTopmost: DWORD = 0x0000_0008
let wsExTransparent: DWORD = 0x0000_0020
let wsExToolWindow: DWORD = 0x0000_0080
let wsExLayered: DWORD = 0x0008_0000
let wsExNoActivate: DWORD = 0x0800_0000

let wmDestroy: UINT = 0x0002
let wmPaint: UINT = 0x000F
let wmNull: UINT = 0x0000
let wmTimer: UINT = 0x0113
let wmWindowPosChanged: UINT = 0x0047
let wmMouseActivate: UINT = 0x0021
let wmLButtonDown: UINT = 0x0201
let wmLButtonUp: UINT = 0x0202
let wmRButtonUp: UINT = 0x0205
let wmContextMenu: UINT = 0x007B
let wmCommand: UINT = 0x0111
let wmApp: UINT = 0x8000
let maNoActivate: LRESULT = 3

let swHide: Int32 = 0
let swShowNoActivate: Int32 = 4

let swpNoSize: UINT = 0x0001
let swpNoMove: UINT = 0x0002
let swpNoZOrder: UINT = 0x0004
let swpNoActivate: UINT = 0x0010

let ulwAlpha: DWORD = 0x0000_0002
let acSrcOver: BYTE = 0x00
let acSrcAlpha: BYTE = 0x01
let biRGB: DWORD = 0
let dibRGBColors: UINT = 0
let srcCopy: DWORD = 0x00CC_0020
let halftone: Int32 = 4

let smCxScreen: Int32 = 0
let smCyScreen: Int32 = 1
let smCxSmIcon: Int32 = 49
let smCySmIcon: Int32 = 50
let spiGetWorkArea: UINT = 0x0030

let nimAdd: DWORD = 0
let nimDelete: DWORD = 2
let nifMessage: UINT = 0x01
let nifIcon: UINT = 0x02
let nifTip: UINT = 0x04

let mfString: UINT = 0x0000
let mfSeparator: UINT = 0x0800
let mfPopup: UINT = 0x0010
let mfByCommand: UINT = 0x0000
let tpmRightButton: UINT = 0x0002

let dtCenter: UINT = 0x0001
let dtVCenter: UINT = 0x0004
let dtSingleLine: UINT = 0x0020
let dtNoPrefix: UINT = 0x0800
let dtCalcRect: UINT = 0x0400
let transparentBackground: Int32 = 1
let fwExtraBold: Int32 = 800
let clearTypeQuality: DWORD = 5

let sndAsync: DWORD = 0x0001
let sndNoDefault: DWORD = 0x0002
let sndMemory: DWORD = 0x0004

/// `HWND_TOPMOST`, a cast in the headers.
let hwndTopmost = HWND(bitPattern: -1)
/// `IDC_ARROW` and `IDI_APPLICATION` are `MAKEINTRESOURCE` casts.
let idcArrow = UnsafePointer<WCHAR>(bitPattern: 32512)
let idiApplication = UnsafePointer<WCHAR>(bitPattern: 32512)

/// A NUL-terminated UTF-16 copy of `string`, for any `LPCWSTR` parameter.
func wide(_ string: String) -> [WCHAR] {
    Array(string.utf16) + [0]
}

/// Registers a window class whose messages go to `procedure`.
func registerClass(_ name: String, procedure: WNDPROC, cursor: Bool = false) {
    let instance = GetModuleHandleW(nil)
    let className = wide(name)
    className.withUnsafeBufferPointer { buffer in
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.lpfnWndProc = procedure
        windowClass.hInstance = instance
        windowClass.lpszClassName = buffer.baseAddress
        if cursor { windowClass.hCursor = LoadCursorW(nil, idcArrow) }
        _ = RegisterClassExW(&windowClass)
    }
}

func createWindow(
    className: String,
    title: String = "",
    style: DWORD,
    exStyle: DWORD,
    x: Int32,
    y: Int32,
    width: Int32,
    height: Int32
) -> HWND? {
    CreateWindowExW(
        exStyle,
        wide(className),
        wide(title),
        style,
        x, y, width, height,
        nil, nil,
        GetModuleHandleW(nil),
        nil
    )
}

/// A 32-bit top-down DIB in a memory DC: the pixels of one layered window.
///
/// `PixelCanvas` already holds premultiplied BGRA, exactly what
/// `UpdateLayeredWindow` wants, so presenting is a straight copy.
final class LayeredSurface {
    let width: Int
    let height: Int
    let deviceContext: HDC
    private let bitmap: HBITMAP
    private let previous: HGDIOBJ?
    let bits: UnsafeMutablePointer<UInt32>

    init?(width: Int, height: Int) {
        guard width > 0, height > 0,
              let screen = GetDC(nil)
        else { return nil }
        defer { ReleaseDC(nil, screen) }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        // Negative height: rows run top to bottom, the same as `PixelCanvas`.
        info.bmiHeader.biHeight = -LONG(height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = biRGB

        var raw: UnsafeMutableRawPointer?
        guard let memory = CreateCompatibleDC(screen),
              let bitmap = CreateDIBSection(screen, &info, dibRGBColors, &raw, nil, 0),
              let raw
        else { return nil }

        self.width = width
        self.height = height
        deviceContext = memory
        self.bitmap = bitmap
        previous = SelectObject(memory, bitmap)
        bits = raw.bindMemory(to: UInt32.self, capacity: width * height)
    }

    deinit {
        SelectObject(deviceContext, previous)
        DeleteObject(bitmap)
        DeleteDC(deviceContext)
    }

    /// Hands out the DIB while it is not selected into the memory DC, for APIs
    /// that refuse a selected bitmap — `CreateIconIndirect`, for one.
    func withDetachedBitmap<Result>(_ body: (HBITMAP) -> Result) -> Result {
        SelectObject(deviceContext, previous)
        defer { SelectObject(deviceContext, bitmap) }
        return body(bitmap)
    }

    func copy(_ canvas: PixelCanvas) {
        let count = min(canvas.width * canvas.height, width * height)
        canvas.pixels.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            bits.update(from: base, count: count)
        }
    }

    /// Pushes the pixels to `window` and moves it so its top-left sits at `x`, `y`.
    func present(to window: HWND, x: Int, y: Int) {
        var destination = POINT(x: LONG(x), y: LONG(y))
        var size = SIZE(cx: LONG(width), cy: LONG(height))
        var source = POINT(x: 0, y: 0)
        var blend = BLENDFUNCTION(
            BlendOp: acSrcOver,
            BlendFlags: 0,
            SourceConstantAlpha: 255,
            AlphaFormat: acSrcAlpha
        )
        UpdateLayeredWindow(window, nil, &destination, &size, deviceContext, &source, 0, &blend, ulwAlpha)
    }
}

/// Moves a window without resizing, activating or re-stacking it.
func move(_ window: HWND, x: Int, y: Int) {
    SetWindowPos(window, nil, Int32(x), Int32(y), 0, 0, swpNoSize | swpNoZOrder | swpNoActivate)
}

/// Lifts a window back to the top of the always-on-top band.
func raiseToTop(_ window: HWND) {
    SetWindowPos(window, hwndTopmost, 0, 0, 0, 0, swpNoSize | swpNoMove | swpNoActivate)
}

/// Seconds on a monotonic clock.
func monotonicSeconds() -> Double {
    var frequency = LARGE_INTEGER()
    var counter = LARGE_INTEGER()
    QueryPerformanceFrequency(&frequency)
    QueryPerformanceCounter(&counter)
    return Double(counter.QuadPart) / Double(frequency.QuadPart)
}
