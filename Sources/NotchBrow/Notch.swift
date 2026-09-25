import AppKit
import NotchBrowCore

extension NSScreen {
    var notchGeometry: DisplayGeometry {
        let width: CGFloat
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea { width = right.minX - left.maxX }
        else { width = 0 }
        return DisplayGeometry(frame: frame, visibleFrame: visibleFrame, safeTop: safeAreaInsets.top, hardwareNotchWidth: width)
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BrowserPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class NotchView: FlippedView {
    var onToggle: (() -> Void)?
    var onMenu: (() -> Void)?
    var onHover: (() -> Void)?
    var onLeave: (() -> Void)?
    var hardware = false
    var expanded = false { didSet { needsDisplay = true } }
    private(set) var hovered = false
    private var tracking: NSTrackingArea?
    private var pendingHover: DispatchWorkItem?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("NotchBrow. Open browser")
        toolTip = "NotchBrow · Click to browse · ⌃⌥Space"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { onToggle?(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true; needsDisplay = true
        pendingHover?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onHover?() }
        pendingHover = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    override func mouseExited(with event: NSEvent) { hovered = false; pendingHover?.cancel(); needsDisplay = true; onLeave?() }
    override func mouseDown(with event: NSEvent) { pendingHover?.cancel(); onToggle?() }
    override func rightMouseDown(with event: NSEvent) { onMenu?() }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(Theme.shell.cgColor)
            context.addPath(NotchShape.path(in: bounds, bottomRadius: expanded ? 0 : 12))
            context.fillPath()
        }
        if !hardware {
            let lens = NSRect(x: w / 2 - 3, y: 10, width: 6, height: 6)
            NSColor(calibratedWhite: 0.075, alpha: 1).setFill(); NSBezierPath(ovalIn: lens).fill()
            NSColor(red: 0.045, green: 0.09, blue: 0.14, alpha: 1).setFill()
            NSBezierPath(ovalIn: lens.insetBy(dx: 1.2, dy: 1.2)).fill()
            NSColor.white.withAlphaComponent(0.09).setFill()
            NSBezierPath(ovalIn: NSRect(x: lens.minX + 1.6, y: lens.minY + 1.3, width: 1.3, height: 1.3)).fill()
        }
        if hovered || expanded {
            Theme.accent.withAlphaComponent(hovered ? 0.9 : 0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: w / 2 - 13, y: h - 4, width: 26, height: 2), xRadius: 1, yRadius: 1).fill()
        }
    }
}

final class FullBrowserWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
