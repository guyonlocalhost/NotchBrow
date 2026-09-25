import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/Icon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let image = NSImage(size: NSSize(width: px, height: px))
        image.lockFocus()
        let c = NSGraphicsContext.current!.cgContext
        c.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        NSColor(red: 0.73, green: 0.86, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200).fill()
        NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 222, y: 216, width: 580, height: 512), xRadius: 70, yRadius: 70).fill()
        NSBezierPath(roundedRect: NSRect(x: 348, y: 638, width: 328, height: 165), xRadius: 45, yRadius: 45).fill()
        NSColor(red: 0.73, green: 0.86, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 281, y: 574, width: 462, height: 46), xRadius: 23, yRadius: 23).fill()
        NSColor.white.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: NSRect(x: 281, y: 452, width: 282, height: 24), xRadius: 12, yRadius: 12).fill()
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: NSRect(x: 281, y: 386, width: 386, height: 20), xRadius: 10, yRadius: 10).fill()
        NSBezierPath(roundedRect: NSRect(x: 281, y: 330, width: 322, height: 20), xRadius: 10, yRadius: 10).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
