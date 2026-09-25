import AppKit
import Carbon
import NotchBrowCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let testing = CommandLine.arguments.contains("--smoke-test")
    lazy var store = BrowserStore(defaults: testing ? UserDefaults(suiteName: "NotchBrow.SmokeTests")! : .standard)
    lazy var browser = BrowserController(store: store, testing: testing)
    @MainActor lazy var updater = AppUpdater(app: self)
    let notch = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let panel = BrowserPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let notchView = NotchView(frame: .zero)
    private var otherNotches: [NSNumber: (panel: NotchPanel, view: NotchView)] = [:]
    var notchPanels: [NotchPanel] { [notch] + otherNotches.values.map(\.panel) }
    private(set) var expanded = false
    private(set) var display: NSScreen?
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var previousApp: NSRunningApplication?
    let reveal = NotchTransition()
    private(set) var browserWindow: FullBrowserWindow?
    private(set) var fullScreenTransitioning = false
    private var enterFullScreenWork: DispatchWorkItem?
    private var pendingReturn = false
    private var pendingTuck = false
    private var hoverOpened = false
    private var hoverDismiss: DispatchWorkItem?
    var currentWindow: NSWindow { browser.windowed ? browserWindow! : panel }
    var isAnimating: Bool { reveal.isAnimating }
    var hotKeyRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if testing { store.defaults.removePersistentDomain(forName: "NotchBrow.SmokeTests") }
        configureNotch(notch, view: notchView); configure(panel)
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.contentViewController = browser
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.browser.escape() }
        browser.onHide = { [weak self] in
            guard let self else { return }
            if self.browser.windowed { self.returnToNotch(tucked: false) } else { self.hide() }
        }
        browser.onFullScreen = { [weak self] in self?.toggleFullScreen() }
        browser.onMenu = { [weak self] view in self?.showMenu(at: view) }
        notchView.onToggle = { [weak self] in self?.toggle() }
        notchView.onHover = { [weak self] in self?.openFromHover() }
        notchView.onLeave = { [weak self] in self?.scheduleHoverDismiss() }
        (browser.view as? ShellView)?.onHoverChanged = { [weak self] inside in
            if inside { self?.hoverDismiss?.cancel() } else { self?.scheduleHoverDismiss() }
        }
        notchView.onMenu = { [weak self] in guard let self else { return }; self.showMenu(at: self.notchView) }
        installMenuBar()
        chooseDisplay(); place()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(restoreNotches), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(restoreNotches), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(restoreNotches), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        installEvents()
        updater.onRestart = { [weak self] in self?.browser.saveTabsForUpdate() }
        if !testing {
            browser.restoreTabsAfterUpdate()
            if let index = CommandLine.arguments.firstIndex(of: "--update-receipt"), CommandLine.arguments.indices.contains(index + 1) {
                try? Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            }
        }
        if testing {
            Task { @MainActor in await SmokeTest.run(app: self) }
        } else if !store.defaults.bool(forKey: "hasLaunched") {
            store.defaults.set(true, forKey: "hasLaunched"); show()
        }
    }
    private func configure(_ window: NSPanel) {
        window.isOpaque = false; window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.isMovable = false; window.animationBehavior = .none
    }
    private func configureNotch(_ window: NotchPanel, view: NotchView) {
        configure(window)
        // Full-screen menu-bar shields sit above ordinary floating/status windows.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.hasShadow = false; window.contentView = view
    }
    private func displayID(_ screen: NSScreen) -> NSNumber {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber
    }
    private func chooseDisplay() {
        if let current = display, let match = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == current.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }) { display = match; return }
        display = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    @objc private func displaysChanged() { chooseDisplay(); place() }
    @objc private func restoreNotches() { chooseDisplay(); updateNotches() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreNotches()
        return false
    }
    private func updateNotches() {
        guard let display else { return }
        notch.setFrame(display.notchGeometry.notchFrame, display: true)
        notchView.hardware = display.notchGeometry.hasNotch; notchView.needsDisplay = true
        let others = NSScreen.screens.filter { displayID($0) != displayID(display) }
        let remaining = Set(others.map(displayID))
        for id in Array(otherNotches.keys) where !remaining.contains(id) {
            otherNotches.removeValue(forKey: id)?.panel.orderOut(nil)
        }
        for screen in others {
            let id = displayID(screen)
            if otherNotches[id] == nil {
                let window = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                let view = NotchView(frame: .zero)
                configureNotch(window, view: view)
                view.onToggle = { [weak self] in self?.openNotch(on: id, hover: false) }
                view.onHover = { [weak self] in self?.openNotch(on: id, hover: true) }
                view.onLeave = { [weak self] in self?.scheduleHoverDismiss() }
                view.onMenu = { [weak self, weak view] in
                    guard let self, let view else { return }; self.showMenu(at: view)
                }
                otherNotches[id] = (window, view)
            }
            let surface = otherNotches[id]!
            surface.panel.setFrame(screen.notchGeometry.notchFrame, display: true)
            surface.view.hardware = screen.notchGeometry.hasNotch; surface.view.needsDisplay = true
        }
        notchPanels.forEach { $0.orderFrontRegardless() }
    }
    private func openNotch(on id: NSNumber, hover: Bool) {
        if browser.windowed {
            if !hover { returnToNotch(tucked: true) }
            return
        }
        guard !hover || (store.hoverToOpen && !expanded),
              let screen = NSScreen.screens.first(where: { displayID($0) == id }) else { return }
        display = screen; place(); show(activate: !hover)
    }
    func place() {
        guard let display else { return }
        let geometry = display.notchGeometry
        updateNotches()
        if !browser.windowed {
            reveal.cancel(on: browser.view)
            panel.setFrame(geometry.browserFrame(large: store.largePanel), display: true)
            browser.view.needsLayout = true; browser.view.layoutSubtreeIfNeeded()
            if !expanded { panel.orderOut(nil) }
        }
    }
    func toggle() { expanded ? hide() : show() }
    func show(activate: Bool = true) {
        hoverDismiss?.cancel()
        if browser.windowed {
            browserWindow?.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true); browserWindow?.makeKeyAndOrderFront(nil); return
        }
        if expanded {
            if activate { hoverOpened = false; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        let reversing = reveal.isAnimating
        if !reversing { place() }
        expanded = true; hoverOpened = !activate; notchView.expanded = true
        browser.setMediaSuspended(false); panel.alphaValue = 1
        reveal.animate(opening: true, view: browser.view, notchWidth: notch.frame.width,
                       reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {}
        if activate {
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); browser.focusAddress()
        } else {
            // Preview without taking keyboard focus from the current app.
            panel.orderFrontRegardless()
        }
    }
    func openFromHover() {
        guard store.hoverToOpen, !expanded, !browser.windowed else { return }
        show(activate: false)
    }
    private func scheduleHoverDismiss() {
        hoverDismiss?.cancel()
        guard hoverOpened, !store.pinned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverOpened, !self.store.pinned, self.browser.modalDepth == 0,
                  !self.panel.frame.contains(NSEvent.mouseLocation), !self.notch.frame.contains(NSEvent.mouseLocation) else { return }
            self.hide(restoreFocus: false)
        }
        hoverDismiss = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func hide(restoreFocus: Bool = true) {
        guard expanded, browser.modalDepth == 0 else { return }
        if browser.windowed { returnToNotch(tucked: true); return }
        hoverDismiss?.cancel(); hoverOpened = false
        expanded = false; notchView.expanded = false; browser.setMediaSuspended(true)
        reveal.animate(opening: false, view: browser.view, notchWidth: notch.frame.width,
                       reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
            guard let self, !self.expanded else { return }; self.panel.orderOut(nil)
        }
        if restoreFocus && NSApp.isActive && previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp?.activate(options: .activateIgnoringOtherApps)
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.browser.windowed, !self.hoverOpened, !self.panel.isKeyWindow,
                  !self.store.pinned, self.browser.modalDepth == 0 else { return }
            self.hide(restoreFocus: false)
        }
    }
    func openBrowserWindow(enterFullScreen: Bool = true) {
        guard !browser.windowed else { return }
        hoverDismiss?.cancel(); hoverOpened = false; reveal.cancel(on: browser.view)
        if browserWindow == nil {
            let window = FullBrowserWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "NotchBrow"; window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Theme.shell; window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 680, height: 440)
            window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
            window.delegate = self; window.onEscape = { [weak self] in self?.escape() }
            browserWindow = window
        }
        browser.windowed = true
        panel.contentViewController = nil; panel.orderOut(nil)
        browserWindow!.contentViewController = browser
        if let screen = display { browserWindow!.setFrame(screen.visibleFrame, display: true) }
        expanded = true; notchView.expanded = false
        updateNotches()
        browser.setMediaSuspended(false)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true); browserWindow!.makeKeyAndOrderFront(nil); browserWindow!.makeMain()
        browser.view.needsLayout = true
        if enterFullScreen {
            // Let AppKit finish promoting the accessory app before starting its Space transition.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.browser.windowed else { return }
                self.enterFullScreenWork = nil
                self.browserWindow?.makeKeyAndOrderFront(nil); self.browserWindow?.makeMain()
                self.browserWindow?.toggleFullScreen(nil)
            }
            enterFullScreenWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    func toggleFullScreen() {
        guard !fullScreenTransitioning, enterFullScreenWork == nil, browser.modalDepth == 0 else { return }
        if !browser.windowed { openBrowserWindow(); return }
        browserWindow?.toggleFullScreen(nil)
    }
    func returnToNotch(tucked: Bool) {
        guard browser.windowed, browser.modalDepth == 0 else { return }
        enterFullScreenWork?.cancel(); enterFullScreenWork = nil
        pendingReturn = true; pendingTuck = tucked
        if fullScreenTransitioning { return }
        if browserWindow?.styleMask.contains(.fullScreen) == true { browserWindow?.toggleFullScreen(nil); return }
        finishReturnToNotch()
    }
    private func finishReturnToNotch() {
        let tucked = pendingTuck
        pendingReturn = false; pendingTuck = false
        browserWindow?.contentViewController = nil; browserWindow?.orderOut(nil)
        browser.windowed = false; browser.fullScreen = false
        panel.contentViewController = browser
        NSApp.setActivationPolicy(.accessory)
        expanded = false; place()
        if tucked {
            notchView.expanded = false; browser.setMediaSuspended(true)
            previousApp?.activate(options: .activateIgnoringOtherApps)
        } else { show() }
        // Activation-policy changes finish asynchronously in AppKit.
        DispatchQueue.main.async { [weak self] in self?.restoreNotches() }
    }
    func windowWillEnterFullScreen(_ notification: Notification) { fullScreenTransitioning = true; if testing { print("FULL SCREEN: will enter") } }
    func windowDidEnterFullScreen(_ notification: Notification) {
        fullScreenTransitioning = false; browser.fullScreen = true
        restoreNotches()
        if pendingReturn { returnToNotch(tucked: pendingTuck) }
    }
    func windowWillExitFullScreen(_ notification: Notification) { fullScreenTransitioning = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenTransitioning = false; browser.fullScreen = false
        if pendingReturn { finishReturnToNotch() }
        restoreNotches()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullScreenTransitioning = false; browser.fullScreen = false; if testing { print("FULL SCREEN: failed to enter") } }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { fullScreenTransitioning = false; pendingReturn = false }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === browserWindow { returnToNotch(tucked: true); return false }
        return true
    }
    private func escape() {
        if browser.fullScreen { toggleFullScreen() } else { browser.escape() }
    }
    private func installEvents() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.outsideClick(NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown { return self.handleKey(event) ? nil : event }
            if event.window === self.panel { self.hoverOpened = false; self.hoverDismiss?.cancel() }
            self.outsideClick(NSEvent.mouseLocation); return event
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            app.toggle(); return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        let id = EventHotKeyID(signature: 0x4E425257, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        hotKeyRegistered = result == noErr
        if !hotKeyRegistered { notchView.toolTip = "NotchBrow · Click to browse (⌃⌥Space is unavailable)" }
    }
    func outsideClick(_ point: NSPoint) {
        guard expanded, !browser.windowed, !store.pinned, browser.modalDepth == 0,
              !panel.frame.contains(point), !notchPanels.contains(where: { $0.frame.contains(point) }) else { return }
        hide(restoreFocus: false)
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard expanded, currentWindow.isKeyWindow, browser.modalDepth == 0 else { return false }
        if event.keyCode == 53 { escape(); return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control), event.keyCode == 48 {
            let direction = flags.contains(.shift) ? -1 : 1
            browser.selectTab((browser.selected + direction + browser.tabs.count) % browser.tabs.count); return true
        }
        guard flags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l": browser.focusAddress()
        case "t": browser.newTab()
        case "w": browser.closeTab()
        case "r": browser.reload()
        case "d": browser.toggleBookmark()
        case "f": if flags.contains(.control) { toggleFullScreen() } else { browser.showFind() }
        case "[": browser.goBack()
        case "]": browser.goForward()
        case "+", "=": browser.zoom(0.1)
        case "-": browser.zoom(-0.1)
        case "0": browser.active.webView.pageZoom = 1
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if let n = Int(event.charactersIgnoringModifiers ?? "") { browser.selectTab(n == 9 ? browser.tabs.count - 1 : n - 1) }
        default: return false
        }
        return true
    }
    private func installMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "NotchBrow")
        statusItem.button?.toolTip = "NotchBrow · ⌃⌥Space · Right-click for menu"
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusPressed)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        let appMenu = NSMenu()
        let updateItem = NSMenuItem(title: "Update NotchBrow…", action: #selector(menuUpdate), keyEquivalent: "")
        updateItem.target = self; appMenu.addItem(updateItem); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit NotchBrow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; menu.addItem(editItem)
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(menuFullScreen), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]; fullScreenItem.target = self; viewMenu.addItem(fullScreenItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: ""); viewItem.submenu = viewMenu; menu.addItem(viewItem)
        NSApp.mainMenu = menu
    }
    @objc private func statusPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp, let b = statusItem.button { showMenu(at: b); return }
        if !browser.windowed, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           display.map({ displayID($0) }) != displayID(screen) {
            display = screen; place(); show()
        } else { toggle() }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self
            if let checked { i.state = checked ? .on : .off }; menu.addItem(i)
        }
        item("\(expanded ? "Tuck away" : "Open browser")    ⌃⌥Space", #selector(menuToggle))
        item("New tab    ⌘T", #selector(menuNewTab))
        menu.addItem(.separator())
        let saved = NSMenuItem(title: "Saved pages", action: nil, keyEquivalent: "")
        let savedMenu = NSMenu()
        for (index, page) in store.bookmarks.enumerated() {
            let i = NSMenuItem(title: page.title, action: #selector(openSaved(_:)), keyEquivalent: ""); i.target = self; i.tag = index; savedMenu.addItem(i)
        }
        if savedMenu.items.isEmpty { let i = NSMenuItem(title: "Save a page with ⌘D", action: nil, keyEquivalent: ""); i.isEnabled = false; savedMenu.addItem(i) }
        saved.submenu = savedMenu; menu.addItem(saved)
        item("Reveal last download", #selector(revealDownload)); menu.items.last?.isEnabled = browser.lastDownload != nil
        menu.addItem(.separator())
        item("Keep browser open", #selector(menuPin), checked: store.pinned)
        let triggerItem = NSMenuItem(title: "Open notch with", action: nil, keyEquivalent: "")
        let triggerMenu = NSMenu()
        for (title, action, on) in [("Click", #selector(menuClick), !store.hoverToOpen), ("Hover", #selector(menuHover), store.hoverToOpen)] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self
            entry.state = on ? .on : .off; triggerMenu.addItem(entry)
        }
        triggerItem.submenu = triggerMenu; menu.addItem(triggerItem)
        item(browser.fullScreen ? "Exit full screen    ⌃⌘F" : "Enter full screen    ⌃⌘F", #selector(menuFullScreen))
        if browser.windowed { item("Return to notch", #selector(menuReturnToNotch)) }
        item("Larger browser", #selector(menuSize), checked: store.largePanel)
        if NSScreen.screens.count > 1 {
            let displays = NSMenuItem(title: "Show on display", action: nil, keyEquivalent: ""); let submenu = NSMenu()
            for (i, screen) in NSScreen.screens.enumerated() {
                let entry = NSMenuItem(title: screen.localizedName, action: #selector(menuDisplay(_:)), keyEquivalent: "")
                entry.target = self; entry.tag = i; entry.state = screen == display ? .on : .off; submenu.addItem(entry)
            }
            displays.submenu = submenu; menu.addItem(displays)
        }
        menu.addItem(.separator())
        item("Update NotchBrow…", #selector(menuUpdate))
        item("About NotchBrow", #selector(about))
        item("Quit NotchBrow    ⌘Q", #selector(quit))
        return menu
    }
    func showMenu(at view: NSView) {
        browser.modalDepth += 1
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
        browser.modalDepth -= 1
    }
    @objc private func menuToggle() { DispatchQueue.main.async { [weak self] in self?.toggle() } }
    @objc private func menuNewTab() { show(); browser.newTab() }
    @objc private func menuPin() { browser.togglePin() }
    @objc private func menuClick() { store.hoverToOpen = false }
    @objc private func menuHover() { store.hoverToOpen = true }
    @objc private func menuFullScreen() { DispatchQueue.main.async { [weak self] in self?.toggleFullScreen() } }
    @objc private func menuReturnToNotch() { DispatchQueue.main.async { [weak self] in self?.returnToNotch(tucked: false) } }
    @objc private func menuSize() { store.largePanel.toggle(); place() }
    @objc private func menuDisplay(_ sender: NSMenuItem) { guard NSScreen.screens.indices.contains(sender.tag) else { return }; display = NSScreen.screens[sender.tag]; place() }
    @objc private func openSaved(_ sender: NSMenuItem) { guard store.bookmarks.indices.contains(sender.tag) else { return }; show(); browser.navigate(store.bookmarks[sender.tag].url) }
    @objc private func revealDownload() { if let url = browser.lastDownload { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func menuUpdate() { DispatchQueue.main.async { [weak self] in self?.updater.start() } }
    @objc private func about() {
        show()
        let alert = NSAlert(); alert.messageText = "NotchBrow \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Update NotchBrow")
        alert.informativeText = "A little space for the whole web.\n\nNative AppKit + WebKit · Intel & Apple silicon\n\n⌃⌥Space  Open / tuck away\n⌘L  Address     ⌘T  New tab     ⌘W  Close tab\n⌘F  Find     ⌘D  Save page     ⌘R  Reload\n⌃Tab  Next tab     ⌘1–9  Switch tabs\n⌘+ / ⌘−  Zoom     Escape  Tuck away\n\nClick the notch or menu bar icon to return."
        browser.modalDepth += 1
        alert.beginSheetModal(for: currentWindow) { [weak self] response in
            self?.browser.modalDepth -= 1
            if response == .alertSecondButtonReturn { self?.menuUpdate() }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }; if let eventHandler { RemoveEventHandler(eventHandler) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
