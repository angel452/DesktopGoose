import GoosePixels
import WinSDK

let trayClass = "DesktopGooseTray"
/// The tray icon reports clicks with this message.
let trayCallbackMessage = wmApp + 1
let tickTimerID: UINT_PTR = 1

/// Menu command identifiers.
enum TrayCommand: Int32 {
    case remindNow = 1
    case shooMemes = 2
    case quit = 3
}

/// The hidden window that owns the tray icon and drives the 60 Hz timer.
let trayProcedure: WNDPROC = { window, message, wParam, lParam in
    switch message {
    case wmTimer where wParam == tickTimerID:
        app?.tick()
        return 0
    case trayCallbackMessage:
        // Without NOTIFYICON_VERSION_4 the mouse message arrives as lParam itself.
        let event = UINT(truncatingIfNeeded: lParam)
        if event == wmRButtonUp || event == wmLButtonUp || event == wmContextMenu, let window {
            app?.tray?.showMenu(owner: window)
        }
        return 0
    case wmCommand:
        // A menu pick arrives here; its identifier is the low word of wParam.
        if let command = TrayCommand(rawValue: Int32(wParam & 0xFFFF)) {
            app?.perform(command)
        }
        return 0
    case wmDestroy:
        PostQuitMessage(0)
        return 0
    default:
        if message == taskbarCreatedMessage, message != 0 {
            // Explorer restarted and forgot every tray icon; put ours back.
            app?.tray?.add()
            return 0
        }
        return DefWindowProcW(window, message, wParam, lParam)
    }
}

let taskbarCreatedMessage = RegisterWindowMessageW(wide("TaskbarCreated"))

/// The goose's tray icon, the Windows twin of the Mac's 🪿 menu.
final class TrayIcon {
    private var data = NOTIFYICONDATAW()
    private let icon: HICON?

    init(owner: HWND, image: PixelImage?) {
        icon = image.flatMap(TrayIcon.makeIcon) ?? LoadIconW(nil, idiApplication)

        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = owner
        data.uID = 1
        data.uFlags = nifMessage | nifIcon | nifTip
        data.uCallbackMessage = trayCallbackMessage
        data.hIcon = icon

        // szTip is a fixed C array, imported as a tuple; write through its bytes.
        let tip = wide("Desktop Goose")
        withUnsafeMutableBytes(of: &data.szTip) { bytes in
            let capacity = bytes.count / MemoryLayout<WCHAR>.size
            let characters = bytes.bindMemory(to: WCHAR.self)
            for index in 0..<min(tip.count, capacity) { characters[index] = tip[index] }
        }
        add()
    }

    func add() {
        Shell_NotifyIconW(nimAdd, &data)
    }

    func remove() {
        Shell_NotifyIconW(nimDelete, &data)
    }

    func showMenu(owner: HWND) {
        guard let menu = CreatePopupMenu() else { return }
        defer { DestroyMenu(menu) }

        AppendMenuW(menu, mfString, UINT_PTR(TrayCommand.remindNow.rawValue), wide("Take a Break Now"))
        AppendMenuW(menu, mfSeparator, 0, nil)
        AppendMenuW(menu, mfString, UINT_PTR(TrayCommand.shooMemes.rawValue), wide("Shoo the Memes"))
        AppendMenuW(menu, mfSeparator, 0, nil)
        AppendMenuW(menu, mfString, UINT_PTR(TrayCommand.quit.rawValue), wide("Quit Desktop Goose"))

        var cursor = POINT()
        GetCursorPos(&cursor)
        // Without this the menu refuses to close when the human clicks elsewhere.
        SetForegroundWindow(owner)
        // The pick comes back as WM_COMMAND to the owner: TrackPopupMenu's return
        // value imports as a Bool in Swift, so TPM_RETURNCMD cannot carry the id.
        TrackPopupMenu(menu, tpmRightButton, cursor.x, cursor.y, 0, owner, nil)
        PostMessageW(owner, wmNull, 0, 0)
    }

    /// A 32-bit alpha icon from a goose frame, sized for the tray.
    private static func makeIcon(from image: PixelImage) -> HICON? {
        let width = Int(GetSystemMetrics(smCxSmIcon))
        let height = Int(GetSystemMetrics(smCySmIcon))
        guard width > 0, height > 0 else { return nil }

        // Square the frame up first so the goose is not squashed.
        let edge = max(image.width, image.height)
        var square = PixelCanvas(width: edge, height: edge)
        square.blit(image, x: (edge - image.width) / 2, y: (edge - image.height) / 2)
        let scaled = square.image.scaledNearest(width: width, height: height)

        guard let surface = LayeredSurface(width: width, height: height),
              let mask = CreateBitmap(Int32(width), Int32(height), 1, 1, nil)
        else { return nil }
        defer { DeleteObject(mask) }

        var canvas = PixelCanvas(width: width, height: height)
        canvas.blit(scaled, x: 0, y: 0)
        surface.copy(canvas)

        guard let color = CreateBitmap(Int32(width), Int32(height), 1, 32, surface.bits) else { return nil }
        defer { DeleteObject(color) }

        var info = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        return CreateIconIndirect(&info)
    }
}
