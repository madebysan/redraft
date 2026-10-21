import AppKit

/// The menu bar owl: brow, round reading glasses, pupils and beak, drawn as a template image.
/// Geometry matches design/menu-bar-icon/owl-2026-10-21/d-variants/D3-glasses.svg (24-unit grid).
enum OwlIcon {
    /// `pupilShift` moves both pupils sideways in grid units, for the "reading" animation.
    static func image(pupilShift: CGFloat = 0, accessibilityDescription: String = "Redraft") -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let unit = side / 24
            let transform = NSAffineTransform()
            transform.scale(by: unit)
            transform.concat()

            NSColor.black.set()

            let lines = NSBezierPath()
            lines.lineWidth = 2
            lines.lineCapStyle = .round
            lines.lineJoinStyle = .round
            // Lenses
            lines.appendOval(in: NSRect(x: 3, y: 10, width: 7, height: 7))
            lines.appendOval(in: NSRect(x: 14, y: 10, width: 7, height: 7))
            // Bridge
            lines.move(to: NSPoint(x: 10, y: 13))
            lines.curve(to: NSPoint(x: 14, y: 13), controlPoint1: NSPoint(x: 11.3, y: 11.4), controlPoint2: NSPoint(x: 12.7, y: 11.4))
            // Brow
            lines.move(to: NSPoint(x: 3, y: 6.5))
            lines.line(to: NSPoint(x: 7, y: 8))
            lines.line(to: NSPoint(x: 17, y: 8))
            lines.line(to: NSPoint(x: 21, y: 6.5))
            // Beak
            lines.move(to: NSPoint(x: 11, y: 19))
            lines.line(to: NSPoint(x: 12, y: 20.3))
            lines.line(to: NSPoint(x: 13, y: 19))
            lines.stroke()

            for x in [6.5, 17.5] {
                NSBezierPath(ovalIn: NSRect(x: x + pupilShift - 1, y: 12.5, width: 2, height: 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
