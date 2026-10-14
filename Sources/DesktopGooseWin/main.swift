import Foundation
import WinSDK

/// The one app instance, reachable from the Win32 window procedures, which are C
/// callbacks and cannot capture anything.
var app: GooseApp?

// Work in physical pixels; the brain still thinks in logical points, so a 150 %
// display gets a goose of the same apparent size and speed as a 100 % one.
SetProcessDPIAware()

registerClass(overlayClass, procedure: overlayProcedure)
registerClass(bubbleClass, procedure: bubbleProcedure, cursor: true)
registerClass(memeClass, procedure: memeProcedure, cursor: true)
registerClass(trayClass, procedure: trayProcedure)

// A hidden window owns the tray icon and the tick timer. Not a message-only window:
// those never hear Explorer's TaskbarCreated broadcast.
guard let trayWindow = createWindow(
    className: trayClass,
    title: "Desktop Goose",
    style: wsPopup,
    exStyle: wsExToolWindow,
    x: 0, y: 0, width: 0, height: 0
) else { exit(1) }

app = GooseApp(trayWindow: trayWindow)
guard app != nil else { exit(1) }

var message = MSG()
while GetMessageW(&message, nil, 0, 0) > 0 {
    TranslateMessage(&message)
    DispatchMessageW(&message)
}
