import AppKit

let env = ProcessInfo.processInfo.environment

// Debug: dump the generated icon to a PNG and exit, to verify drawing.
if let dump = env["AISTATUS_DUMP_ICON"] {
    let img = StatusIcon.image(r: 1, y: 0.16, g: 0.16)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: dump))
        FileHandle.standardError.write("wrote \(dump) size=\(img.size) pixels=\(rep.pixelsWide)x\(rep.pixelsHigh)\n".data(using: .utf8)!)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
