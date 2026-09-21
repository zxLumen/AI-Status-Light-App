import AppKit

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// Draws the menu bar icon: a mini vertical traffic light (red / yellow / green),
/// with the active lamp lit per the current pattern.
enum StatusIcon {
    static let red = NSColor(hex: "#e8453c")
    static let yellow = NSColor(hex: "#f4c20d")
    static let green = NSColor(hex: "#1faa59")
    static let dim: Double = 0.16

    static func image(r: Double, y: Double, g: Double) -> NSImage {
        let w: CGFloat = 13, h: CGFloat = 18
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        let colors = [red, yellow, green]
        let levels = [max(dim, r), max(dim, y), max(dim, g)]
        let d: CGFloat = 5.4
        let gap: CGFloat = 1.4
        var top = h - 0.6 - d
        for i in 0..<3 {
            let rect = NSRect(x: (w - d) / 2, y: top, width: d, height: d)
            if levels[i] > 0.55 {
                colors[i].withAlphaComponent(0.35 * levels[i]).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: -1.6, dy: -1.6)).fill()
            }
            colors[i].withAlphaComponent(levels[i]).setFill()
            NSBezierPath(ovalIn: rect).fill()
            top -= (d + gap)
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}
