import AppKit
import NotchBrowCore

final class HomeView: FlippedView {
    var onSearch: (() -> Void)?
    var onNavigate: ((String) -> Void)?
    private let eyebrow = Theme.label("A BROWSER, WITHIN REACH", size: 10, weight: .semibold, color: Theme.accent)
    private let heading = Theme.label("A little space.\nFor the whole web.", size: 35, weight: .semibold)
    private let subtitle = Theme.label("Look something up. Get back to your flow.", size: 14, color: Theme.muted)
    private let section = Theme.label("QUICK VISITS", size: 10, weight: .medium, color: Theme.muted)
    private let hint = Theme.label("⌃⌥Space to open   ·   esc to tuck away", size: 12, color: Theme.muted)
    private var tiles: [NSButton] = []
    private lazy var search = SearchLauncher { [weak self] in self?.onSearch?() }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = Theme.surface.cgColor
        heading.maximumNumberOfLines = 2
        [eyebrow, heading, subtitle, section, hint, search].forEach { addSubview($0) }
        search.bezelStyle = .regularSquare; search.isBordered = false
        search.wantsLayer = true; search.layer?.backgroundColor = Theme.elevated.cgColor; search.layer?.cornerRadius = 10
        search.contentTintColor = Theme.text; search.alignment = .left
        search.setAccessibilityLabel("Search or enter a website, Command L")
        update(bookmarks: [])
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(bookmarks: [SavedPage]) {
        tiles.forEach { $0.removeFromSuperview() }
        let pages = bookmarks.isEmpty ? [SavedPage(title: "Wikipedia", url: "https://wikipedia.org"), SavedPage(title: "DuckDuckGo", url: "https://duckduckgo.com"), SavedPage(title: "GitHub", url: "https://github.com")] : Array(bookmarks.prefix(4))
        section.stringValue = bookmarks.isEmpty ? "QUICK VISITS" : "SAVED PAGES"
        tiles = pages.map { page in
            let b = ClosureButton(page.title) { [weak self] in self?.onNavigate?(page.url) }
            b.toolTip = page.url; b.bezelStyle = .regularSquare; b.isBordered = false
            b.wantsLayer = true; b.layer?.backgroundColor = Theme.elevated.cgColor; b.layer?.cornerRadius = 10
            b.contentTintColor = Theme.text
            b.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
            b.imagePosition = .imageTrailing
            addSubview(b); return b
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let width = min(540, bounds.width - 64), x = (bounds.width - width) / 2
        let y = max(24, (bounds.height - 370) / 2)
        eyebrow.frame = NSRect(x: x, y: y, width: width, height: 16)
        heading.frame = NSRect(x: x, y: y + 32, width: width, height: 92)
        subtitle.frame = NSRect(x: x, y: y + 132, width: width, height: 20)
        search.frame = NSRect(x: x, y: y + 176, width: width, height: 46)
        section.frame = NSRect(x: x, y: y + 248, width: width, height: 16)
        let tileWidth = (width - CGFloat(tiles.count - 1) * 10) / CGFloat(max(tiles.count, 1))
        for (i, tile) in tiles.enumerated() { tile.frame = NSRect(x: x + CGFloat(i) * (tileWidth + 10), y: y + 276, width: tileWidth, height: 48) }
        hint.frame = NSRect(x: x, y: min(bounds.height - 30, y + 352), width: width, height: 18)
    }
}
