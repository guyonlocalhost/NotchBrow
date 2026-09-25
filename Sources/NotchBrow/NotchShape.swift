import AppKit

/// Camera housing with a flat bottom when connected to the open browser.
enum NotchShape {
    static func path(in rect: CGRect, bottomRadius: CGFloat = 12) -> CGPath {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        let s: CGFloat = 7
        let r = min(bottomRadius, (w - 2 * s) / 2, h - s)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y))
        p.addCurve(to: CGPoint(x: x + w - s, y: y + s),
                   control1: CGPoint(x: x + w - 4, y: y), control2: CGPoint(x: x + w - s, y: y + 3))
        p.addLine(to: CGPoint(x: x + w - s, y: y + h - r))
        p.addCurve(to: CGPoint(x: x + w - s - r, y: y + h),
                   control1: CGPoint(x: x + w - s, y: y + h - r * 0.42), control2: CGPoint(x: x + w - s - r * 0.42, y: y + h))
        p.addLine(to: CGPoint(x: x + s + r, y: y + h))
        p.addCurve(to: CGPoint(x: x + s, y: y + h - r),
                   control1: CGPoint(x: x + s + r * 0.42, y: y + h), control2: CGPoint(x: x + s, y: y + h - r * 0.42))
        p.addLine(to: CGPoint(x: x + s, y: y + s))
        p.addCurve(to: CGPoint(x: x, y: y),
                   control1: CGPoint(x: x + s, y: y + 3), control2: CGPoint(x: x + 4, y: y))
        p.closeSubpath()
        return p
    }
}
