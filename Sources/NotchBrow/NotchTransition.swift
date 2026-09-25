import AppKit
import QuartzCore

/// Animate a compositor mask, keeping WebKit's viewport fixed throughout the reveal.
/// Reversals start from the current presentation path instead of snapping to an endpoint.
final class NotchTransition {
    private var mask: CAShapeLayer?
    private var generation = 0
    private(set) var isAnimating = false

    func cancel(on view: NSView) {
        generation += 1; isAnimating = false
        mask?.removeAllAnimations(); mask = nil; view.layer?.mask = nil
    }

    func animate(opening: Bool, view: NSView, notchWidth: CGFloat, reducedMotion: Bool, completion: @escaping () -> Void) {
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        generation += 1
        let token = generation
        let rect = layer.bounds
        let width = min(notchWidth - 14, rect.width)
        let compact = CGRect(x: rect.midX - width / 2, y: layer.isGeometryFlipped ? rect.minY : rect.maxY - 2,
                             width: width, height: 2)
        let closedPath = CGPath(roundedRect: compact, cornerWidth: 1, cornerHeight: 1, transform: nil)
        let openPath = CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)
        let shape = mask ?? CAShapeLayer()
        let from = shape.presentation()?.path ?? shape.path ?? (opening ? closedPath : openPath)
        shape.removeAllAnimations()
        shape.frame = rect
        shape.fillColor = NSColor.black.cgColor
        let to = opening ? openPath : closedPath
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shape.path = to; layer.mask = shape
        CATransaction.commit()
        mask = shape
        if reducedMotion {
            isAnimating = false; layer.mask = nil; mask = nil; completion(); return
        }
        isAnimating = true
        let duration = opening ? 0.38 : 0.26
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = from; animation.toValue = to; animation.duration = duration
        animation.timingFunction = opening
            ? CAMediaTimingFunction(controlPoints: 0.16, 0.85, 0.22, 1)
            : CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 0.2)
        shape.add(animation, forKey: "notchReveal")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak view] in
            guard let self, self.generation == token else { return }
            self.isAnimating = false
            view?.layer?.mask = nil; self.mask = nil
            completion()
        }
    }
}
