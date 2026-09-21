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

/// Menu bar icon: a single glossy "glass" orb. Radial-gradient sphere with a
/// top-left specular highlight and a soft glow when active. Rendered at 2x for
/// smooth edges on Retina; opacity follows the pattern intensity.
enum StatusIcon {
    static let red = NSColor(hex: "#e8453c")
    static let yellow = NSColor(hex: "#f4c20d")
    static let green = NSColor(hex: "#1faa59")
    static let idleGray = NSColor(hex: "#8a8f98")
    static let dim: Double = 0.16

    static let canvas: CGFloat = 22
    static let orbDiameter: CGFloat = 13

    static func lighten(_ c: NSColor, _ f: CGFloat) -> NSColor { c.blended(withFraction: f, of: .white) ?? c }
    static func darken(_ c: NSColor, _ f: CGFloat) -> NSColor { c.blended(withFraction: f, of: .black) ?? c }

    static func blendedColor(r: Double, y: Double, g: Double) -> NSColor {
        let rr = max(0, r), yy = max(0, y), gg = max(0, g)
        let total = rr + yy + gg
        guard total > 0.02 else { return idleGray }
        func comp(_ c: NSColor) -> (CGFloat, CGFloat, CGFloat) {
            let cc = c.usingColorSpace(.sRGB) ?? c
            return (cc.redComponent, cc.greenComponent, cc.blueComponent)
        }
        let (r1, g1, b1) = comp(red)
        let (r2, g2, b2) = comp(yellow)
        let (r3, g3, b3) = comp(green)
        return NSColor(
            srgbRed: (CGFloat(rr) * r1 + CGFloat(yy) * r2 + CGFloat(gg) * r3) / CGFloat(total),
            green:   (CGFloat(rr) * g1 + CGFloat(yy) * g2 + CGFloat(gg) * g3) / CGFloat(total),
            blue:    (CGFloat(rr) * b1 + CGFloat(yy) * b2 + CGFloat(gg) * b3) / CGFloat(total),
            alpha: 1)
    }

    static func intensity(r: Double, y: Double, g: Double) -> Double {
        let m = max(r, max(y, g))
        return m < 0.02 ? dim : min(1, max(dim, m))
    }

    static func image(r: Double, y: Double, g: Double) -> NSImage {
        let color = blendedColor(r: r, y: y, g: g)
        let i = CGFloat(max(0.08, intensity(r: r, y: y, g: g)))
        let d = orbDiameter
        let scale = 2
        let px = Int(canvas * CGFloat(scale))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: canvas, height: canvas)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        let sphere = NSRect(x: canvas / 2 - d / 2, y: canvas / 2 - d / 2, width: d, height: d)

        // soft glow
        NSGraphicsContext.saveGraphicsState()
        if i > 0.5 {
            let sh = NSShadow()
            sh.shadowColor = color.withAlphaComponent(0.55 * i)
            sh.shadowBlurRadius = 3
            sh.shadowOffset = .zero
            sh.set()
        }
        NSGradient(starting: lighten(color, 0.45).withAlphaComponent(i),
                   ending: darken(color, 0.12).withAlphaComponent(i))?
            .draw(in: NSBezierPath(ovalIn: sphere), relativeCenterPosition: NSPoint(x: -0.35, y: 0.35))
        NSGraphicsContext.restoreGraphicsState()

        // specular highlight
        let hl = NSRect(x: sphere.minX + sphere.width * 0.20,
                        y: sphere.minY + sphere.height * 0.52,
                        width: sphere.width * 0.40, height: sphere.height * 0.30)
        NSGradient(starting: NSColor.white.withAlphaComponent(0.75 * i),
                   ending: NSColor.white.withAlphaComponent(0))?
            .draw(in: NSBezierPath(ovalIn: hl), relativeCenterPosition: .zero)

        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: NSSize(width: canvas, height: canvas))
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }
}
