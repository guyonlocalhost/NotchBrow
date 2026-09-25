import AppKit
@preconcurrency import WebKit
import NotchBrowCore

final class BrowserTab {
    let webView: WKWebView
    var observations: [NSKeyValueObservation] = []
    var isHome = true
    var error: String?
    var requestedURL: URL?
    var title: String {
        if error != nil { return requestedURL?.host ?? "Page unavailable" }
        return isHome ? "New tab" : (webView.title?.isEmpty == false ? webView.title! : (webView.url?.host ?? "Loading…"))
    }
    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = Theme.surface
    }
}

final class BrowserController: NSViewController, NSSearchFieldDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let store: BrowserStore
    let testing: Bool
    var onHide: (() -> Void)?
    var onFullScreen: (() -> Void)?
    var windowed = false { didSet { updateWindowMode() } }
    var fullScreen = false { didSet { updateWindowMode() } }
    var onMenu: ((NSView) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var tabs: [BrowserTab] = []
    private(set) var selected = 0
    var active: BrowserTab { tabs[selected] }
    var modalDepth = 0
    private(set) var lastDownload: URL?
    var testDownloadDirectory: URL?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var retainedDownloads: [ObjectIdentifier: WKDownload] = [:]
    let address = NSSearchField()
    let home = HomeView(frame: .zero)
    private let content = FlippedView()
    private let toolbar = FlippedView()
    private let tabScroll = NSScrollView()
    private let tabRow = FlippedView()
    private(set) var tabViews: [BrowserTabView] = []
    private let footer = Theme.label("Ready when you are", size: 11, color: Theme.muted)
    private let engine = Theme.label("WEBKIT", size: 9, weight: .medium, color: Theme.muted)
    private let progress = NSProgressIndicator()
    private let errorView = FlippedView()
    private let errorTitle = Theme.label("This page couldn’t open", size: 23, weight: .semibold)
    private let errorDetail = Theme.label("", size: 13, color: Theme.muted)
    private lazy var retry = ClosureButton("Try again") { [weak self] in self?.reload() }
    private let findField = NSSearchField()
    private var findVisible = false
    private var buttons: [ActionButton] = []
    private lazy var backButton = ActionButton(symbol: "chevron.left", label: "Back · ⌘[") { [weak self] in self?.goBack() }
    private lazy var forwardButton = ActionButton(symbol: "chevron.right", label: "Forward · ⌘]") { [weak self] in self?.goForward() }
    private lazy var reloadButton = ActionButton(symbol: "arrow.clockwise", label: "Reload · ⌘R") { [weak self] in self?.reload() }
    private lazy var bookmarkButton = ActionButton(symbol: "bookmark", label: "Save page · ⌘D") { [weak self] in self?.toggleBookmark() }
    private lazy var pinButton = ActionButton(symbol: "pin", label: "Keep open when clicking away") { [weak self] in self?.togglePin() }
    private lazy var sizeButton = ActionButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Enter full screen · ⌃⌘F") { [weak self] in self?.onFullScreen?() }
    private lazy var menuButton: ActionButton = ActionButton(symbol: "ellipsis", label: "Browser menu") { [weak self] in guard let self else { return }; self.onMenu?(self.menuButton) }
    private lazy var hideButton = ActionButton(symbol: "chevron.up", label: "Tuck away · Escape") { [weak self] in self?.onHide?() }
    private lazy var addButton = ActionButton(symbol: "plus", label: "New tab · ⌘T") { [weak self] in self?.newTab() }

    init(store: BrowserStore, testing: Bool = false) { self.store = store; self.testing = testing; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = ShellView(frame: NSRect(x: 0, y: 0, width: 860, height: 620))
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        content.wantsLayer = true; content.layer?.cornerRadius = 12; content.layer?.masksToBounds = true
        [toolbar, tabScroll, content, footer, engine, progress, findField, addButton].forEach { view.addSubview($0) }
        buttons = [backButton, forwardButton, reloadButton, bookmarkButton, pinButton, sizeButton, menuButton, hideButton]
        buttons.forEach { toolbar.addSubview($0) }
        address.sendsWholeSearchString = true; address.sendsSearchStringImmediately = false
        address.isEditable = true; address.isSelectable = true
        address.font = .systemFont(ofSize: 13); address.textColor = Theme.text
        address.backgroundColor = Theme.elevated; address.isBezeled = true; address.bezelStyle = .roundedBezel; address.drawsBackground = true
        address.focusRingType = .exterior; address.placeholderAttributedString = NSAttributedString(string: "Search or enter a website", attributes: [.foregroundColor: Theme.muted])
        address.cell?.isScrollable = true; address.cell?.wraps = false; address.cell?.usesSingleLineMode = true
        address.wantsLayer = true; address.layer?.cornerRadius = 8; address.layer?.masksToBounds = true; address.delegate = self
        address.target = self; address.action = #selector(submitAddress)
        address.setAccessibilityLabel("Search or website address")
        toolbar.addSubview(address)
        tabScroll.documentView = tabRow; tabScroll.drawsBackground = false
        tabScroll.hasHorizontalScroller = false; tabScroll.hasVerticalScroller = false
        tabScroll.verticalScrollElasticity = .none; tabScroll.horizontalScrollElasticity = .automatic
        content.addSubview(home)
        home.onSearch = { [weak self] in self?.focusAddress() }
        home.onNavigate = { [weak self] text in self?.navigate(text) }
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.controlSize = .small; progress.isHidden = true
        findField.placeholderString = "Find in page"; findField.target = self; findField.action = #selector(findNext)
        findField.isHidden = true; findField.setAccessibilityLabel("Find in page")
        errorView.wantsLayer = true; errorView.layer?.backgroundColor = Theme.surface.cgColor
        [errorTitle, errorDetail, retry].forEach { errorView.addSubview($0) }
        errorDetail.maximumNumberOfLines = 4; errorDetail.lineBreakMode = .byWordWrapping
        errorView.isHidden = true; content.addSubview(errorView)
        newTab(focus: false)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width, h = view.bounds.height
        let top = fullScreen ? view.safeAreaInsets.top : 0
        toolbar.frame = NSRect(x: 12, y: 8 + top, width: w - 24, height: 40)
        backButton.frame = NSRect(x: 0, y: 2, width: 32, height: 34)
        forwardButton.frame = NSRect(x: 32, y: 2, width: 32, height: 34)
        reloadButton.frame = NSRect(x: 64, y: 2, width: 32, height: 34)
        let right: [ActionButton] = [bookmarkButton, pinButton, sizeButton, menuButton, hideButton]
        for (i, b) in right.enumerated() { b.frame = NSRect(x: toolbar.bounds.width - CGFloat(5 - i) * 34, y: 2, width: 34, height: 34) }
        address.frame = NSRect(x: 104, y: 5, width: max(80, toolbar.bounds.width - 284), height: 28)
        tabScroll.frame = NSRect(x: 16, y: 52 + top, width: w - 72, height: 32)
        addButton.frame = NSRect(x: w - 48, y: 51 + top, width: 32, height: 32)
        let findHeight: CGFloat = findVisible ? 36 : 0
        findField.frame = NSRect(x: w - 294, y: 87 + top, width: 274, height: 26)
        content.frame = NSRect(x: 10, y: 88 + top + findHeight, width: w - 20, height: max(50, h - 118 - top - findHeight))
        home.frame = content.bounds
        if !tabs.isEmpty { active.webView.frame = content.bounds }
        errorView.frame = content.bounds
        let errorWidth = min(460, content.bounds.width - 64)
        let errorX = (content.bounds.width - errorWidth) / 2
        errorTitle.frame = NSRect(x: errorX, y: 90, width: errorWidth, height: 35)
        errorDetail.frame = NSRect(x: errorX, y: 140, width: errorWidth, height: 90)
        retry.frame = NSRect(x: errorX, y: 242, width: 100, height: 32)
        progress.frame = NSRect(x: 22, y: 84 + top, width: w - 44, height: 3)
        footer.frame = NSRect(x: 22, y: h - 23, width: w - 122, height: 16)
        engine.frame = NSRect(x: w - 71, y: h - 22, width: 52, height: 14)
    }
    @discardableResult func newTab(configuration: WKWebViewConfiguration? = nil, focus: Bool = true) -> BrowserTab {
        let config = configuration ?? WKWebViewConfiguration()
        if testing && configuration == nil { config.websiteDataStore = .nonPersistent() }
        let tab = BrowserTab(configuration: config)
        tab.webView.navigationDelegate = self; tab.webView.uiDelegate = self
        tabs.append(tab)
        tab.observations = [
            tab.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.refresh() },
            tab.webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.refresh() },
            tab.webView.observe(\.title, options: [.new]) { [weak self] _, _ in self?.refresh(); self?.rebuildTabs() },
            tab.webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.refresh() }
        ]
        selectTab(tabs.count - 1)
        if focus { focusAddress() }
        return tab
    }
    func saveTabsForUpdate() {
        store.defaults.set(tabs.map { $0.isHome ? "" : ($0.webView.url ?? $0.requestedURL)?.absoluteString ?? "" }, forKey: "updateTabs")
        store.defaults.set(selected, forKey: "updateSelectedTab")
        store.defaults.synchronize()
    }
    func restoreTabsAfterUpdate() {
        guard let urls = store.defaults.stringArray(forKey: "updateTabs"), !urls.isEmpty else { return }
        let selectedTab = store.defaults.integer(forKey: "updateSelectedTab")
        store.defaults.removeObject(forKey: "updateTabs"); store.defaults.removeObject(forKey: "updateSelectedTab")
        for (index, string) in urls.enumerated() {
            if index > 0 { newTab(focus: false) }
            if let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { navigate(string) }
        }
        selectTab(min(max(selectedTab, 0), tabs.count - 1))
    }
    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs.forEach { $0.webView.removeFromSuperview() }
        selected = index
        if !active.isHome { content.addSubview(active.webView, positioned: .below, relativeTo: errorView) }
        home.isHidden = !active.isHome
        home.update(bookmarks: store.bookmarks)
        address.stringValue = active.isHome ? "" : ((active.error == nil ? active.webView.url : active.requestedURL)?.absoluteString ?? "")
        refresh(); rebuildTabs(); view.needsLayout = true
        tabViews[index].scrollToVisible(tabViews[index].bounds)
    }
    func closeTab(_ index: Int? = nil) {
        let i = index ?? selected
        guard tabs.indices.contains(i) else { return }
        tabs[i].webView.stopLoading(); tabs[i].webView.removeFromSuperview(); tabs[i].observations.removeAll()
        tabs.remove(at: i)
        if tabs.isEmpty { newTab(); return }
        let next = i < selected ? selected - 1 : min(selected, tabs.count - 1)
        selectTab(next)
    }
    func rebuildTabs() {
        // Keep the controls alive on title/selection updates so mouse tracking and focus stay stable.
        if tabViews.count != tabs.count {
            tabViews.forEach { $0.removeFromSuperview() }
            tabViews = tabs.indices.map { index in
                let tab = BrowserTabView(select: { [weak self] in self?.selectTab(index) }, close: { [weak self] in self?.closeTab(index) })
                tabRow.addSubview(tab); return tab
            }
        }
        tabRow.frame = NSRect(x: 0, y: 0, width: CGFloat(tabs.count) * 190, height: 32)
        for (index, tab) in tabs.enumerated() {
            let item = tabViews[index]
            item.frame = NSRect(x: CGFloat(index) * 190, y: 1, width: 184, height: 30)
            item.selectedTab = index == selected
            if item.titleButton.title != tab.title { item.titleButton.title = tab.title; item.titleButton.needsDisplay = true }
            item.titleButton.toolTip = tab.title
            item.titleButton.setAccessibilityLabel("Tab \(index + 1): \(tab.title)\(index == selected ? ", selected" : "")")
            item.closeButton.setAccessibilityLabel("Close \(tab.title)")
            item.closeButton.toolTip = "Close \(tab.title)"
            item.needsLayout = true
        }
    }
    private func updateWindowMode() {
        guard isViewLoaded else { return }
        (view as? ShellView)?.edgeToEdge = windowed
        let label = fullScreen ? "Exit full screen · ⌃⌘F" : "Enter full screen · ⌃⌘F"
        sizeButton.image = NSImage(systemSymbolName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", accessibilityDescription: label)
        sizeButton.toolTip = label; sizeButton.setAccessibilityLabel(label)
        pinButton.isHidden = windowed
        hideButton.toolTip = windowed ? "Return to notch" : "Tuck away · Escape"
        hideButton.setAccessibilityLabel(hideButton.toolTip)
        view.needsLayout = true
    }
    func navigate(_ text: String) {
        guard let url = AddressResolver.resolve(text) else { return }
        active.isHome = false; active.error = nil; active.requestedURL = url
        home.isHidden = true; errorView.isHidden = true
        content.addSubview(active.webView, positioned: .below, relativeTo: errorView)
        active.webView.frame = content.bounds
        address.stringValue = url.absoluteString; view.window?.makeFirstResponder(active.webView)
        active.webView.load(URLRequest(url: url)); refresh(); rebuildTabs()
    }
    @objc func submitAddress() { navigate(address.stringValue) }
    func focusAddress() { view.window?.makeFirstResponder(address); address.selectText(nil) }
    func goBack() { active.webView.goBack() }
    func goForward() { active.webView.goForward() }
    func reload() {
        if active.webView.isLoading { active.webView.stopLoading() }
        else if let url = (active.error == nil ? active.webView.url : active.requestedURL) ?? active.requestedURL { active.error = nil; refresh(); active.webView.load(URLRequest(url: url)) }
        else if !address.stringValue.isEmpty { navigate(address.stringValue) }
    }
    func togglePin() { store.pinned.toggle(); refresh(); onStateChange?() }
    func toggleBookmark() {
        guard !active.isHome, let url = active.webView.url, ["https", "http"].contains(url.scheme ?? "") else { return }
        store.toggleBookmark(SavedPage(title: active.title, url: url.absoluteString)); refresh()
    }
    func refresh() {
        guard !tabs.isEmpty, isViewLoaded else { return }
        let tab = active, web = tab.webView
        if windowed { view.window?.title = tab.isHome ? "NotchBrow" : tab.title + " — NotchBrow" }
        backButton.isEnabled = web.canGoBack; forwardButton.isEnabled = web.canGoForward
        reloadButton.image = NSImage(systemSymbolName: web.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: web.isLoading ? "Stop loading" : "Reload")
        progress.isHidden = !web.isLoading; progress.doubleValue = web.estimatedProgress
        pinButton.selectedState = store.pinned
        bookmarkButton.selectedState = tab.error == nil && store.bookmarks.contains { $0.url == web.url?.absoluteString }
        bookmarkButton.isEnabled = !tab.isHome && web.url != nil && tab.error == nil
        errorView.isHidden = tab.error == nil
        errorDetail.stringValue = tab.error ?? ""
        if address.currentEditor() == nil { address.stringValue = tab.isHome ? "" : ((tab.error == nil ? web.url : tab.requestedURL)?.absoluteString ?? tab.requestedURL?.absoluteString ?? address.stringValue) }
        if web.isLoading { footer.stringValue = "Loading \(web.url?.host ?? "page")…" }
        else if let error = tab.error { footer.stringValue = error }
        else if tab.isHome { footer.stringValue = store.pinned ? "Pinned · stays open until you tuck it away" : "Your next thought, one click away" }
        else { footer.stringValue = "\(web.hasOnlySecureContent ? "Secure connection" : "Connection is not fully secure") · \(web.url?.host ?? "Page")\(store.pinned ? " · Pinned" : "")" }
    }
    func setMediaSuspended(_ suspended: Bool) { tabs.forEach { $0.webView.setAllMediaPlaybackSuspended(suspended, completionHandler: nil) } }
    func showFind() {
        findVisible = true; findField.isHidden = false; view.needsLayout = true; view.window?.makeFirstResponder(findField)
    }
    func escape() {
        if findVisible { findVisible = false; findField.isHidden = true; view.needsLayout = true; view.window?.makeFirstResponder(active.webView) }
        else { onHide?() }
    }
    @objc func findNext() {
        let config = WKFindConfiguration(); config.wraps = true
        active.webView.find(findField.stringValue, configuration: config) { [weak self] result in
            self?.footer.stringValue = result.matchFound ? "Match found" : "No matches on this page"
        }
    }
    func zoom(_ delta: Double) { active.webView.pageZoom = min(3, max(0.5, active.webView.pageZoom + delta)) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tabs.first(where: { $0.webView === webView })?.error = nil; refresh()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh(); rebuildTabs() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error) }
    private func navigationFailed(_ webView: WKWebView, _ error: Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled, code != 102 else { return }
        tabs.first(where: { $0.webView === webView })?.error = error.localizedDescription + " Check the address or your connection, then try again."
        refresh(); rebuildTabs()
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tabs.first(where: { $0.webView === webView })?.error = "The page stopped responding. Choose Try again to reload it."
        refresh()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["http", "https", "about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
            if navigationAction.targetFrame?.isMainFrame == true, !navigationAction.shouldPerformDownload {
                tabs.first(where: { $0.webView === webView })?.requestedURL = url
            }
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated, ["mailto", "tel"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let tab = newTab(configuration: configuration, focus: false); tab.isHome = false; selectTab(selected); return tab.webView
    }
    func webViewDidClose(_ webView: WKWebView) { if let i = tabs.firstIndex(where: { $0.webView === webView }) { closeTab(i) } }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; modalDepth += 1
        panel.beginSheetModal(for: view.window!) { [weak self] result in self?.modalDepth -= 1; completionHandler(result == .OK ? panel.urls : nil) }
    }
    private func dialog(_ message: String, webView: WKWebView, buttons: [String], input: String? = nil, completion: @escaping (NSApplication.ModalResponse, String?) -> Void) {
        let alert = NSAlert(); alert.messageText = webView.url?.host ?? "Website"; alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        var field: NSTextField?
        if let input { field = NSTextField(string: input); field?.frame = NSRect(x: 0, y: 0, width: 300, height: 24); alert.accessoryView = field }
        modalDepth += 1
        alert.beginSheetModal(for: view.window!) { [weak self] result in self?.modalDepth -= 1; completion(result, field?.stringValue) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialog(message, webView: webView, buttons: ["OK"]) { _, _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialog(message, webView: webView, buttons: ["OK", "Cancel"]) { result, _ in completionHandler(result == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        dialog(prompt, webView: webView, buttons: ["OK", "Cancel"], input: defaultText ?? "") { result, text in completionHandler(result == .alertFirstButtonReturn ? text : nil) }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { retain(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { retain(download) }
    private func retain(_ download: WKDownload) { retainedDownloads[ObjectIdentifier(download)] = download; download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        if testing, let directory = testDownloadDirectory {
            let url = directory.appendingPathComponent((suggestedFilename as NSString).lastPathComponent)
            downloadDestinations[ObjectIdentifier(download)] = url
            completionHandler(url)
            return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        modalDepth += 1
        panel.beginSheetModal(for: view.window!) { [weak self] result in
            guard let self else { completionHandler(nil); return }
            self.modalDepth -= 1
            let url = result == .OK ? panel.url : nil
            if let url { self.downloadDestinations[ObjectIdentifier(download)] = url; self.footer.stringValue = "Downloading \(url.lastPathComponent)…" }
            completionHandler(url)
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        lastDownload = downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        retainedDownloads.removeValue(forKey: ObjectIdentifier(download))
        footer.stringValue = "Saved \(lastDownload?.lastPathComponent ?? "download") · Reveal from the browser menu"
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download)); retainedDownloads.removeValue(forKey: ObjectIdentifier(download))
        footer.stringValue = "Download failed: \(error.localizedDescription)"
    }
}
