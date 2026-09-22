#!/usr/bin/env swift
//
// Renders the app icon: a dark squircle "housing" with three vertical glass
// lamps (red / yellow / green), matching the floating light's shell style.
//
// Writes:
//   Resources/AppIcon.iconset/   (per-size PNGs)
//   Resources/AppIcon.icns       (via `iconutil`)
//   docs/images/icon-1024.png    (for the README)
//
// Run:  swift scripts/make-icon.swift   (or `make icon`)
//
import AppKit
import Foundation

// MARK: - palette (kept in sync with Sources/AIStatusLight/StatusIcon.swift)

func hexColor(_ s: String) -> NSColor {
    var t = s
    if t.hasPrefix("#") { t.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: t).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func lighten(_ c: NSColor, _ f: CGFloat) -> NSColor { c.blended(withFraction: f, of: .white) ?? c }
func darken(_ c: NSColor, _ f: CGFloat) -> NSColor { c.blended(withFraction: f, of: .black) ?? c }

let lampColors = [hexColor("#e8453c"), hexColor("#f4c20d"), hexColor("#1faa59")]

// MARK: - drawing

/// `size` is the canvas edge in points; all geometry derives from it so the same
/// composition renders crisply at every size. `detail` drops the glow / specular
/// highlights for the tiny sizes where they only muddy the pixels.
func render(size: CGFloat, detail: Bool) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let u = size / 1024.0                       // scale from the 1024 design grid
    let content = 824 * u                       // macOS icon grid: 824 of 1024
    let inset = (size - content) / 2
    let squircle = NSRect(x: inset, y: inset, width: content, height: content)
    let corner = content * 0.2237

    // Squircle body: dark gradient + drop shadow.
    let body = NSBezierPath(roundedRect: squircle, xRadius: corner, yRadius: corner)
    NSGraphicsContext.saveGraphicsState()
    if detail {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
        sh.shadowBlurRadius = 18 * u
        sh.shadowOffset = NSSize(width: 0, height: -8 * u)
        sh.set()
    }
    NSGradient(starting: NSColor(white: 0.26, alpha: 1),
               ending: NSColor(white: 0.08, alpha: 1))?.draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Inner rim light.
    NSColor.white.withAlphaComponent(detail ? 0.14 : 0.10).setStroke()
    let rim = NSBezierPath(roundedRect: squircle.insetBy(dx: 1.5 * u, dy: 1.5 * u),
                           xRadius: corner - 1.5 * u, yRadius: corner - 1.5 * u)
    rim.lineWidth = max(1, 2 * u)
    rim.stroke()

    // Housing: vertical rounded body holding the lamps.
    let hw = content * 0.52
    var d = hw * 0.47
    var gap = d * 0.22
    var margin = d * 0.30
    if !detail { d = hw * 0.58; gap = d * 0.20; margin = d * 0.18 }   // chunkier when tiny
    let hh = 3 * d + 2 * gap + 2 * margin
    let housing = NSRect(x: (size - hw) / 2, y: (size - hh) / 2, width: hw, height: hh)
    let hCorner = hw * 0.20
    let hPath = NSBezierPath(roundedRect: housing, xRadius: hCorner, yRadius: hCorner)
    NSGradient(starting: NSColor(white: 0.30, alpha: 1),
               ending: NSColor(white: 0.10, alpha: 1))?.draw(in: hPath, angle: -90)
    NSColor.black.withAlphaComponent(0.5).setStroke()
    hPath.lineWidth = max(1, 1.5 * u)
    hPath.stroke()
    if detail {
        NSGraphicsContext.saveGraphicsState()
        hPath.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.16),
                   ending: NSColor.white.withAlphaComponent(0))?.draw(
            in: NSRect(x: housing.minX, y: housing.midY,
                       width: housing.width, height: housing.height / 2),
            angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Lamps, top → bottom: red, yellow, green.
    for (i, color) in lampColors.enumerated() {
        let cy = housing.maxY - margin - d / 2 - CGFloat(i) * (d + gap)
        let orb = NSRect(x: size / 2 - d / 2, y: cy - d / 2, width: d, height: d)

        if detail {                                        // recessed socket
            let socket = NSBezierPath(ovalIn: orb.insetBy(dx: -d * 0.10, dy: -d * 0.10))
            NSColor(white: 0.16, alpha: 1).setFill()
            socket.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            socket.lineWidth = max(1, d * 0.03)
            socket.stroke()
        }

        NSGraphicsContext.saveGraphicsState()              // glow + orb
        if detail {
            let sh = NSShadow()
            sh.shadowColor = color.withAlphaComponent(0.55)
            sh.shadowBlurRadius = d * 0.28
            sh.shadowOffset = .zero
            sh.set()
        }
        NSGradient(starting: lighten(color, 0.45), ending: darken(color, 0.12))?
            .draw(in: NSBezierPath(ovalIn: orb),
                  relativeCenterPosition: NSPoint(x: -0.35, y: 0.35))
        NSGraphicsContext.restoreGraphicsState()

        if detail {                                        // specular highlight
            let hl = NSRect(x: orb.minX + orb.width * 0.20, y: orb.minY + orb.height * 0.52,
                            width: orb.width * 0.40, height: orb.height * 0.30)
            NSGradient(starting: NSColor.white.withAlphaComponent(0.75),
                       ending: NSColor.white.withAlphaComponent(0))?
                .draw(in: NSBezierPath(ovalIn: hl), relativeCenterPosition: .zero)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let png1024 = root.appendingPathComponent("docs/images/icon-1024.png")

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: png1024.deletingLastPathComponent(), withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, pixels) in entries {
    let rep = render(size: CGFloat(pixels), detail: pixels > 32)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

if let data = render(size: 1024, detail: true).representation(using: .png, properties: [:]) {
    try data.write(to: png1024)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

print("iconset: \(iconset.path)")
print("icns:    \(icns.path)")
print("png:     \(png1024.path)")
