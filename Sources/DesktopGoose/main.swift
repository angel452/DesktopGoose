import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
// .accessory: no Dock icon, no menu bar. The goose lives in the status bar.
application.setActivationPolicy(.accessory)
application.run()
