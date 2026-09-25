import AppKit
import WebKit
import NotchBrowCore

@MainActor enum SmokeTest {
    static func run(app: AppDelegate) async {
        let args = CommandLine.arguments
        let output = args.firstIndex(of: "--smoke-test").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "/tmp/NotchBrow-smoke"
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        var checks: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            func check(_ condition: Bool, _ label: String) throws {
                guard condition else { throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
                checks.append(label); print("PASS: \(label)"); fflush(stdout)
            }
            try check(!app.expanded && app.notchPanels.count == NSScreen.screens.count && app.notchPanels.allSatisfy(\.isVisible), "Cold launch shows a resting notch on every connected display")
            try check(NSScreen.screens.allSatisfy { screen in
                app.notchPanels.contains { $0.frame == screen.notchGeometry.notchFrame && $0.contentView?.bounds.size == screen.notchGeometry.notchSize }
            }, "Every notch has visible content at its display's top center")
            app.notchPanels.forEach { $0.orderOut(nil) }
            _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
            try check(!app.expanded && app.notchPanels.allSatisfy(\.isVisible), "Reopening restores hidden notches even when the menu bar icon is visible")
            if let secondary = app.notchPanels.first(where: { $0 !== app.notch }) {
                let targetFrame = secondary.frame
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: secondary.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                (secondary.contentView as! NotchView).mouseDown(with: click)
                try await wait { app.expanded && !app.isAnimating }
                try check(app.notch.frame == targetFrame && abs(app.panel.frame.midX - targetFrame.midX) < 1, "Clicking another display's notch opens the browser on that display")
                app.hide(restoreFocus: false)
                try await wait { !app.isAnimating && !app.panel.isVisible }
                try check(app.notchPanels.count == NSScreen.screens.count && app.notchPanels.allSatisfy(\.isVisible), "Switching displays and tucking the browser retains every notch")
            }
            app.show()
            try await wait(timeout: 5) { app.panel.isKeyWindow && !app.isAnimating }
            try check(app.expanded && app.panel.isVisible && app.panel.canBecomeKey, "Browser opens as a focusable panel")
            try check(NSApp.activationPolicy() == .accessory, "No Dock icon or standard app window")
            try check(app.hotKeyRegistered, "Global Control-Option-Space shortcut registered")
            try check(app.notch.isVisible && app.notch.frame.maxY == app.display?.frame.maxY, "Notch is attached flush to display top")
            try check(app.panel.frame.maxY == app.notch.frame.minY + 1, "Browser retains its original position beneath the notch")
            let addressOnScreen = app.panel.convertToScreen(app.browser.address.convert(app.browser.address.bounds, to: nil))
            try check(addressOnScreen.maxY < app.notch.frame.minY, "Browser controls stay below the camera housing")
            try snapshot(app.browser.view, to: directory.appendingPathComponent("home.png"))
            try snapshot(app.notchView, to: directory.appendingPathComponent("notch.png"))
            try snapshotAssembly(app, to: directory.appendingPathComponent("notch-browser.png"))
            let preview = FlippedView(frame: NSRect(x: 0, y: 0, width: 600, height: 110))
            preview.wantsLayer = true; preview.layer?.backgroundColor = NSColor(calibratedWhite: 0.68, alpha: 1).cgColor
            let restingNotch = NotchView(frame: NSRect(x: 207, y: 0, width: 186, height: 30))
            preview.addSubview(restingNotch)
            try snapshot(preview, to: directory.appendingPathComponent("simulated-notch.png"))
            let browser = app.browser
            try check(app.makeMenu().item(withTitle: "Update NotchBrow…")?.action != nil, "Update action is available from browser and notch menus")
            app.updater.start()
            try check(app.updater.isUpdating && app.currentWindow.attachedSheet != nil, "Update button opens native progress UI")
            app.currentWindow.endSheet(app.currentWindow.attachedSheet!, returnCode: .cancel)
            try await wait { !app.updater.isUpdating && app.currentWindow.attachedSheet == nil }
            try check(browser.modalDepth == 0 && app.expanded, "Cancelling an update leaves the browser and notch available")
            let focusEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: app.panel.windowNumber, context: nil, characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
            try check(app.handleKey(focusEvent) && browser.address.currentEditor() != nil, "Command-L focuses the editable address control")
            browser.address.stringValue = "example.com"
            try check(browser.address.sendAction(browser.address.action!, to: browser.address.target), "Native address control submits navigation")
            try await wait { browser.active.webView.title == "Example Domain" && !browser.active.webView.isLoading }
            try check(browser.active.webView.url?.host == "example.com", "Real HTTPS page loads through WKWebView")
            browser.newTab(focus: false); browser.selectTab(0); browser.saveTabsForUpdate()
            let restored = BrowserController(store: app.store, testing: true)
            _ = restored.view; restored.restoreTabsAfterUpdate()
            try check(restored.tabs.count == 2 && restored.selected == 0 && !restored.tabs[0].isHome && restored.tabs[1].isHome,
                      "Update restart restores page URLs, blank tabs, and selected tab")
            try check(app.store.defaults.object(forKey: "updateTabs") == nil, "Update session is consumed once without changing ordinary startup")
            restored.tabs.forEach { $0.webView.stopLoading() }; browser.closeTab(1)
            let result = try await browser.active.webView.evaluateJavaScript("document.querySelector('h1').textContent")
            try check(result as? String == "Example Domain", "WebKit renders and executes JavaScript")
            let image = try await browser.active.webView.takeSnapshot(configuration: nil)
            try image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }?.write(to: directory.appendingPathComponent("web-page.png"))
            let web = browser.active.webView
            let viewport = web.frame
            _ = try await web.evaluateJavaScript("window.notchBrowContinuity = 42; true")
            app.hide(restoreFocus: false)
            try await Task.sleep(nanoseconds: 70_000_000)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                try check(app.isAnimating && browser.view.layer?.mask != nil, "Closing uses an animated compositor mask")
            }
            app.show()
            try await wait { !app.isAnimating && app.panel.isKeyWindow }
            try check(app.expanded && app.panel.isVisible && browser.view.layer?.mask == nil, "Interrupted collapse reverses cleanly into an open panel")
            try check(web.frame == viewport, "Animation keeps the WebKit viewport stable")
            app.hide(restoreFocus: false)
            try await wait { !app.isAnimating && !app.panel.isVisible }
            let hoverEvent = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: app.notch.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            app.store.hoverToOpen = false
            app.notchView.mouseEntered(with: hoverEvent)
            try await Task.sleep(nanoseconds: 250_000_000)
            try check(!app.expanded, "Click mode ignores hovering")
            app.notchView.mouseExited(with: hoverEvent)
            let triggerMenu = app.makeMenu().item(withTitle: "Open notch with")!.submenu!
            let hoverItem = triggerMenu.item(withTitle: "Hover")!
            NSApp.sendAction(hoverItem.action!, to: hoverItem.target, from: hoverItem)
            try check(app.store.hoverToOpen, "Opening mode can be changed to Hover in the menu")
            app.notchView.mouseEntered(with: hoverEvent)
            try await wait { app.expanded && !app.isAnimating }
            try check(app.panel.isVisible && !app.panel.isKeyWindow, "Hover opens without stealing keyboard focus")
            app.notchView.mouseDown(with: hoverEvent)
            app.notchView.mouseExited(with: hoverEvent)
            try await wait { !app.isAnimating && !app.panel.isVisible }
            app.notchView.mouseEntered(with: hoverEvent)
            app.notchView.mouseExited(with: hoverEvent)
            try await Task.sleep(nanoseconds: 250_000_000)
            try check(!app.expanded, "Passing briefly over the notch cancels opening")
            let clickItem = triggerMenu.item(withTitle: "Click")!
            NSApp.sendAction(clickItem.action!, to: clickItem.target, from: clickItem)
            try check(!app.store.hoverToOpen, "Opening mode switches back to Click")
            app.show()
            try await wait { !app.isAnimating && app.panel.isKeyWindow }
            let tabControl = browser.tabViews[0]
            browser.rebuildTabs()
            try check(browser.tabViews[0] === tabControl, "Title refresh preserves existing tab controls")
            browser.view.layoutSubtreeIfNeeded()
            try check(abs(tabControl.titleButton.frame.midY - tabControl.closeButton.frame.midY) < 0.5, "Tab title and close control share a vertical center")
            try snapshot(browser.view, to: directory.appendingPathComponent("tabs.png"))
            app.toggleFullScreen()
            try await wait(timeout: 15) { browser.fullScreen && !app.fullScreenTransitioning && app.currentWindow.isKeyWindow }
            try check(app.browserWindow!.styleMask.contains(.fullScreen), "Expand enters native macOS full screen")
            try check(browser.view.window === app.browserWindow && !app.panel.isVisible, "Browser moves to one full-size window")
            try await wait { notchesAreOnscreen(app) }
            try check(notchesAreOnscreen(app), "Notches remain onscreen over the native full-screen browser")
            try check(app.browserWindow!.frame.width >= app.browserWindow!.screen!.frame.width - 2, "Full-screen browser uses the display width")
            try check(browser.active.webView === web, "Full screen preserves the existing WebKit instance")
            try check(try await web.evaluateJavaScript("window.notchBrowContinuity") as? Int == 42, "Full screen preserves live page state")
            try snapshot(browser.view, to: directory.appendingPathComponent("full-screen.png"))
            let escapeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: app.currentWindow.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            try check(app.handleKey(escapeEvent), "Escape is handled in full screen")
            try await wait(timeout: 15) { !browser.fullScreen && !app.fullScreenTransitioning }
            try check(browser.windowed && app.browserWindow!.styleMask.contains(.resizable), "Leaving full screen restores a resizable browser window")
            app.outsideClick(NSPoint(x: -10000, y: -10000))
            try check(app.browserWindow!.isVisible, "Window mode stays open when switching apps")
            app.returnToNotch(tucked: false)
            try await wait { !browser.windowed && !app.isAnimating && app.panel.isKeyWindow }
            try check(browser.active.webView === web && app.notch.isVisible && NSApp.activationPolicy() == .accessory, "Returning to the notch preserves tabs and removes the ordinary window")
            try check(app.notchPanels.count == NSScreen.screens.count && app.notchPanels.allSatisfy(\.isVisible), "Returning from full screen restores every display's notch")
            app.toggleFullScreen()
            app.returnToNotch(tucked: false)
            try await Task.sleep(nanoseconds: 450_000_000)
            try check(!browser.windowed && !browser.fullScreen && app.panel.isVisible && app.browserWindow?.isVisible == false, "Returning immediately cancels a pending full-screen request")
            app.toggleFullScreen()
            try await wait(timeout: 15) { browser.fullScreen && !app.fullScreenTransitioning && app.currentWindow.isKeyWindow }
            app.browserWindow!.standardWindowButton(.closeButton)!.performClick(nil)
            try await wait(timeout: 15) { !browser.windowed && !app.fullScreenTransitioning && notchesAreOnscreen(app) }
            try await Task.sleep(nanoseconds: 600_000_000)
            try check(!app.expanded && !app.panel.isVisible && app.browserWindow?.isVisible == false && notchesAreOnscreen(app), "Native close from full screen leaves every notch onscreen after the Space transition")
            try check(browser.active.webView === web, "Closing the full-screen window preserves the browsing session")
            _ = app.notchView.accessibilityPerformPress()
            try await wait { app.expanded && !app.isAnimating && app.panel.isKeyWindow }
            try check(app.panel.isVisible, "The retained notch reopens the browser after closing full screen")
            browser.navigate("https://example.com/?notchbrow=2")
            try await wait { !browser.active.webView.isLoading && browser.active.webView.url?.query == "notchbrow=2" }
            try check(browser.active.webView.canGoBack, "Navigation creates real back history")
            browser.goBack()
            try await wait { !browser.active.webView.isLoading && browser.active.webView.url?.query == nil }
            try check(browser.active.webView.canGoForward, "Back navigation preserves forward history")
            browser.toggleBookmark()
            try check(browser.store.bookmarks.count == 1, "Saving a page persists its URL")
            browser.newTab()
            try check(browser.tabs.count == 2 && browser.active.isHome, "New tab opens native home")
            browser.selectTab(0)
            try check(browser.active.webView.title == "Example Domain", "Switching tabs preserves page state")
            browser.closeTab(1)
            try check(browser.tabs.count == 1, "Closing another tab keeps active page")
            if let base = ProcessInfo.processInfo.environment["NOTCHBROW_TEST_BASE_URL"] {
                browser.navigate(base)
                try await wait { browser.active.webView.title == "NotchBrow fixture" && !browser.active.webView.isLoading }
                try check(browser.active.webView.url?.host == "127.0.0.1", "Local HTTP websites load")
                _ = try await browser.active.webView.evaluateJavaScript("document.getElementById('newtab').click(); true")
                try await wait { browser.tabs.count == 2 && browser.active.webView.url?.path == "/second" && !browser.active.webView.isLoading }
                try check(browser.tabs.count == 2, "Target-blank links open inside a browser tab")
                browser.closeTab()
                browser.testDownloadDirectory = directory
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("notchbrow-test.txt"))
                _ = try await browser.active.webView.evaluateJavaScript("document.getElementById('download').click(); true")
                try await wait { browser.lastDownload != nil }
                let downloaded = try String(contentsOf: browser.lastDownload!, encoding: .utf8)
                try check(downloaded == "NotchBrow download verified.\n", "WebKit downloads complete with exact file contents")
                browser.navigate("https://example.com")
                try await wait { browser.active.webView.title == "Example Domain" && !browser.active.webView.isLoading }
            }
            app.store.pinned = true
            app.outsideClick(NSPoint(x: -10000, y: -10000))
            try check(app.expanded, "Pinned browser ignores outside clicks")
            app.store.pinned = false
            app.outsideClick(NSPoint(x: -10000, y: -10000))
            try await wait { !app.isAnimating && !app.panel.isVisible }
            try check(!app.expanded && !app.panel.isVisible && app.notch.isVisible, "Click-away hides browser and retains notch")
            app.show()
            try check(browser.active.webView.title == "Example Domain", "Tucking away preserves loaded page")
            let failedURL = ProcessInfo.processInfo.environment["NOTCHBROW_TEST_BASE_URL"].map { $0 + "/disconnect" } ?? "http://127.0.0.1:65534/notchbrow-unreachable"
            browser.navigate(failedURL)
            try await wait { browser.active.error != nil }
            try check(browser.active.error != nil, "Failed navigation shows a recoverable error")
            try check(browser.address.stringValue == failedURL, "Failed page keeps the attempted address visible")
            try snapshot(browser.view, to: directory.appendingPathComponent("error.png"))
            browser.reload()
            try check(browser.active.error == nil && browser.active.requestedURL?.absoluteString == failedURL, "Retry starts another request for the failed address")
            try await wait { browser.active.error != nil }
            browser.closeTab()
            try check(browser.tabs.count == 1 && browser.active.isHome, "Closing last tab returns to usable home")
            if let executable = ProcessInfo.processInfo.environment["NOTCHBROW_OVERLAY_FIXTURE"] {
                app.hide(restoreFocus: false)
                try await wait { !app.isAnimating && !app.panel.isVisible }
                let stateURL = directory.appendingPathComponent("overlay-fixture.json")
                try? FileManager.default.removeItem(at: stateURL)
                let fixture = Process(), input = Pipe()
                fixture.executableURL = URL(fileURLWithPath: executable)
                fixture.arguments = [stateURL.path, String((app.display!.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value)]
                fixture.standardInput = input
                defer { if fixture.isRunning { fixture.terminate() } }
                try fixture.run()
                func state() -> [String: Any] {
                    guard let data = try? Data(contentsOf: stateURL) else { return [:] }
                    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                }
                try await wait { state()["stage"] as? String == "windowed" && notchesAreOnscreen(app) }
                try check(!NSApp.isActive && notchesAreAbove(app, windowNumber: state()["window"] as! Int), "Notches stay above a different app's window while NotchBrow is inactive")
                input.fileHandleForWriting.write(Data("fullscreen\n".utf8))
                try await wait(timeout: 15) { state()["stage"] as? String == "fullscreen" && notchesAreOnscreen(app) }
                try check(!NSApp.isActive && notchesAreAbove(app, windowNumber: state()["window"] as! Int), "Notches stay above another app's native full-screen Space")
                input.fileHandleForWriting.write(Data("fullscreen\n".utf8))
                try await wait(timeout: 15) { state()["stage"] as? String == "windowed" && notchesAreOnscreen(app) }
                try check(notchesAreOnscreen(app), "Notches persist after another app leaves its full-screen Space")
                // Activate through the notch while the other app is still running. Quitting
                // the foreground fixture first races macOS's asynchronous focus restoration.
                _ = app.notchView.accessibilityPerformPress()
                try await wait(label: "browser focus from a notch above another app") { app.panel.isKeyWindow && !app.isAnimating }
                try check(app.panel.isVisible && notchesAreOnscreen(app), "The notch opens a focusable browser over another application")
                input.fileHandleForWriting.write(Data("quit\n".utf8))
                try await wait(label: "overlay test app to exit") { !fixture.isRunning }
                try await wait(label: "notches after the overlay test app exits") { notchesAreOnscreen(app) }
            }
            let report: [String: Any] = ["passed": checks, "count": checks.count, "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString, "hardwareNotch": app.display?.notchGeometry.hasNotch ?? false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("report.json"))
            print("SMOKE TEST PASSED (\(checks.count) checks)")
            app.hide(restoreFocus: false)
            try await wait { !app.isAnimating }
            app.store.defaults.removePersistentDomain(forName: "NotchBrow.SmokeTests")
            NSApp.terminate(nil)
        } catch {
            print("WINDOW STATE: windowed=\(app.browser.windowed), full=\(app.browser.fullScreen), transition=\(app.fullScreenTransitioning), style=\(app.browserWindow?.styleMask.rawValue ?? 0), key=\(app.currentWindow.isKeyWindow), main=\(app.currentWindow.isMainWindow), canMain=\(app.currentWindow.canBecomeMain), behavior=\(app.currentWindow.collectionBehavior.rawValue), policy=\(NSApp.activationPolicy().rawValue), active=\(NSApp.isActive), visible=\(app.browserWindow?.isVisible ?? false), frame=\(String(describing: app.browserWindow?.frame))")
            try? snapshot(app.browser.view, to: directory.appendingPathComponent("failure-view.png"))
            let message = "SMOKE TEST FAILED: \(error.localizedDescription)\nPassed: \(checks.joined(separator: ", "))"
            try? message.write(to: directory.appendingPathComponent("failure.txt"), atomically: true, encoding: .utf8)
            fputs(message + "\n", stderr); exit(1)
        }
    }
    static func wait(timeout: Double = 25, label: String = "the app state", until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline { throw NSError(domain: "SmokeTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(label)"]) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    static func notchesAreOnscreen(_ app: AppDelegate) -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = Set(windows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
        return app.notchPanels.allSatisfy { $0.isVisible && visible.contains($0.windowNumber) }
    }
    static func notchesAreAbove(_ app: AppDelegate, windowNumber: Int) -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let ordered = windows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue }
        guard let behind = ordered.firstIndex(of: windowNumber) else { return false }
        return app.notchPanels.allSatisfy { notch in
            guard let index = ordered.firstIndex(of: notch.windowNumber) else { return false }
            return index < behind
        }
    }
    static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "Snapshot", code: 1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Snapshot", code: 2) }
        try data.write(to: url)
    }
    static func snapshotAssembly(_ app: AppDelegate, to url: URL) throws {
        let browserTop = app.notch.frame.maxY - app.panel.frame.maxY
        let preview = FlippedView(frame: NSRect(x: 0, y: 0, width: app.panel.frame.width + 80, height: browserTop + app.panel.frame.height + 32))
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor(calibratedRed: 0.28, green: 0.31, blue: 0.26, alpha: 1).cgColor
        for (view, frame) in [(app.browser.view, NSRect(origin: NSPoint(x: 40, y: browserTop), size: app.panel.frame.size)),
                              (app.notchView, NSRect(x: 40 + app.notch.frame.minX - app.panel.frame.minX, y: 0, width: app.notch.frame.width, height: app.notch.frame.height))] {
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "Snapshot", code: 1) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let imageView = NSImageView(frame: frame)
            imageView.image = NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size)
            preview.addSubview(imageView)
        }
        try snapshot(preview, to: url)
    }
}
