import AppKit

// A separate application used to exercise cross-app and native Space visibility.
final class OverlayFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let stateURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let displayID = UInt32(CommandLine.arguments[2])!
    var window: NSWindow!
    var input = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main!
        window = NSWindow(contentRect: screen.visibleFrame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "NotchBrow overlay test"
        window.backgroundColor = .systemBlue
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeMain()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.publish("windowed") }
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self else { return }
                guard !data.isEmpty else { NSApp.terminate(nil); return }
                self.input += String(decoding: data, as: UTF8.self)
                while let end = self.input.firstIndex(of: "\n") {
                    let command = String(self.input[..<end]); self.input.removeSubrange(...end)
                    if command == "fullscreen" { self.window.toggleFullScreen(nil) }
                    if command == "quit" { self.publish("quitting"); NSApp.terminate(nil) }
                }
            }
        }
    }
    func publish(_ stage: String) {
        let state: [String: Any] = ["stage": stage, "window": window.windowNumber, "active": NSApp.isActive]
        try! JSONSerialization.data(withJSONObject: state).write(to: stateURL, options: .atomic)
    }
    func windowDidEnterFullScreen(_ notification: Notification) { publish("fullscreen") }
    func windowDidExitFullScreen(_ notification: Notification) { publish("windowed") }
}

let app = NSApplication.shared
let delegate = OverlayFixture()
app.delegate = delegate
app.run()
