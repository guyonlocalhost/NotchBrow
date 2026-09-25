import AppKit

enum Theme {
    static let shell = NSColor.black
    static let surface = NSColor(calibratedWhite: 0.095, alpha: 1)
    static let elevated = NSColor(calibratedWhite: 0.15, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.94, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.62, alpha: 1)
    static let accent = NSColor(red: 0.70, green: 0.86, blue: 0.72, alpha: 1)
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = Theme.text) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ActionButton: NSButton {
    var invoke: (() -> Void)?
    var selectedState = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var hovered = false
    init(symbol: String, label: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly; isBordered = false
        contentTintColor = Theme.muted
        toolTip = label; setAccessibilityLabel(label)
        target = self; self.action = #selector(pressed)
        invoke = action; focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || selectedState {
            (selectedState ? Theme.accent.withAlphaComponent(0.13) : Theme.elevated).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
        contentTintColor = selectedState ? Theme.accent : (hovered ? Theme.text : Theme.muted)
        super.draw(dirtyRect)
    }
}

final class ClosureButton: NSButton {
    var invoke: (() -> Void)?
    init(_ title: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; invoke = action; target = self; self.action = #selector(pressed)
        bezelStyle = .rounded; font = .systemFont(ofSize: 13)
    }
    @objc private func pressed() { invoke?() }
    required init?(coder: NSCoder) { fatalError() }
}

final class ShellView: FlippedView {
    var edgeToEdge = false { didSet { needsDisplay = true } }
    var onHoverChanged: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
    override func draw(_ dirtyRect: NSRect) {
        Theme.shell.setFill()
        if edgeToEdge { bounds.fill(); return }
        NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22).fill()
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
        stroke.lineWidth = 1; stroke.stroke()
    }
}

final class SearchLauncher: NSButton {
    var invoke: (() -> Void)?
    init(action: @escaping () -> Void) {
        super.init(frame: .zero)
        title = "Search or enter a website"; invoke = action; isBordered = false
        target = self; self.action = #selector(pressed)
        setAccessibilityLabel("Search or enter a website, Command L")
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
    override func draw(_ dirtyRect: NSRect) {
        Theme.elevated.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.text]
        title.draw(at: NSPoint(x: 16, y: bounds.midY - 8), withAttributes: attrs)
        "⌘L".draw(at: NSPoint(x: bounds.maxX - 38, y: bounds.midY - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.muted])
    }
}

/// A real tab hit target with a shared, centered baseline and a separate close control.
final class TabTitleButton: NSButton {
    var selectedTab = false { didSet { needsDisplay = true } }
    var invoke: (() -> Void)?
    override var isFlipped: Bool { true }
    init(action: @escaping () -> Void) {
        super.init(frame: .zero)
        invoke = action; target = self; self.action = #selector(pressed)
        isBordered = false; focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 12, weight: selectedTab ? .medium : .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: selectedTab ? Theme.text : Theme.muted, .paragraphStyle: paragraph
        ]
        let height = ceil(font.ascender - font.descender + font.leading)
        let rect = NSRect(x: 12, y: floor((bounds.height - height) / 2), width: max(0, bounds.width - 18), height: height)
        (title as NSString).draw(in: rect, withAttributes: attributes)
    }
}

final class BrowserTabView: FlippedView {
    let titleButton: TabTitleButton
    let closeButton: ActionButton
    var selectedTab = false { didSet { titleButton.selectedTab = selectedTab; needsDisplay = true } }
    init(select: @escaping () -> Void, close: @escaping () -> Void) {
        titleButton = TabTitleButton(action: select)
        closeButton = ActionButton(symbol: "xmark", label: "Close tab", action: close)
        super.init(frame: .zero)
        addSubview(titleButton); addSubview(closeButton)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        titleButton.frame = NSRect(x: 0, y: 0, width: bounds.width - 30, height: bounds.height)
        closeButton.frame = NSRect(x: bounds.width - 30, y: 1, width: 28, height: bounds.height - 2)
    }
    override func draw(_ dirtyRect: NSRect) {
        if selectedTab {
            Theme.elevated.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
    }
}
