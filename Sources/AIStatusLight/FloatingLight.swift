import AppKit
import SwiftUI

// MARK: - Settings (persisted)

final class FloatingSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var visible: Bool { didSet { d.set(visible, forKey: "floating.visible") } }
    @Published var pinned: Bool { didSet { d.set(pinned, forKey: "floating.pinned") } }
    @Published var allScreens: Bool { didSet { d.set(allScreens, forKey: "floating.allScreens") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "floating.opacity") } }

    init() {
        visible = d.object(forKey: "floating.visible") as? Bool ?? true
        pinned = d.object(forKey: "floating.pinned") as? Bool ?? false
        allScreens = d.object(forKey: "floating.allScreens") as? Bool ?? false
        opacity = d.object(forKey: "floating.opacity") as? Double ?? 1.0
    }
}

// MARK: - Lamps (three glossy orbs, vertical, transparent)

struct FloatingLamps: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: FloatingSettings

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let lv = Pattern.levels(state.mode, t)
                let w = geo.size.width, h = geo.size.height
                let d = max(6, min(w * 0.82, h / 3 * 0.76))
                VStack(spacing: (h - d * 3) / 4) {
                    lamp(lv.r, StatusIcon.red, d)
                    lamp(lv.y, StatusIcon.yellow, d)
                    lamp(lv.g, StatusIcon.green, d)
                }
                .frame(width: w, height: h)
            }
        }
        .opacity(settings.opacity)
        .allowsHitTesting(false)
    }

    /// One stable view tree per lamp (no `if` branch) so the lit/unlit transition
    /// never swaps subtrees each frame — that was causing the stutter. Brightness
    /// is expressed through colour + opacity; the glow is a gradient layer instead
    /// of `.shadow` (no offscreen rendering).
    private func lamp(_ level: Double, _ color: NSColor, _ d: CGFloat) -> some View {
        let on = CGFloat(max(0, min(1, level)))
        let housing = NSColor(white: 0.26, alpha: 1)
        let body = housing.blended(withFraction: on, of: color) ?? color
        let light = StatusIcon.lighten(body, 0.22)
        return ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(nsColor: color).opacity(0.55 * on),
                             Color(nsColor: color).opacity(0)],
                    center: .center, startRadius: d * 0.45, endRadius: d * 0.95))
                .frame(width: d * 1.9, height: d * 1.9)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(nsColor: light), Color(nsColor: body)],
                    center: UnitPoint(x: 0.34, y: 0.30), startRadius: 0, endRadius: d * 0.72))
                .frame(width: d, height: d)
            Ellipse().fill(.white)
                .frame(width: d * 0.36, height: d * 0.24)
                .offset(x: -d * 0.16, y: -d * 0.24)
                .opacity(0.5 * Double(on))
            Circle()
                .strokeBorder(Color.black.opacity(0.25), lineWidth: max(0.6, d * 0.03))
                .frame(width: d, height: d)
        }
        .frame(width: d, height: d)
        .opacity(0.5 + 0.5 * Double(on))
        .compositingGroup()
    }
}

// MARK: - Root NSView: hover controls, background drag, corner resize, scroll zoom

final class FloatingRootView: NSView {
    weak var panel: NSPanel?
    var onTogglePin: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpacityDelta: ((CGFloat) -> Void)?
    private(set) var pinned = false

    private let hosting: NSView
    private let controls = NSView()
    private let pinButton = NSButton()
    private let closeButton = NSButton()
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var resizing = false
    private var resizeStart = NSPoint.zero
    private var startFrame = NSRect.zero

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: hosting.frame)
        wantsLayer = true
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)

        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        controls.layer?.cornerRadius = 6
        controls.isHidden = true
        addSubview(controls)

        func style(_ b: NSButton, _ symbol: String, _ action: Selector, _ tip: String) {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            b.imagePosition = .imageOnly
            b.imageScaling = .scaleProportionallyDown
            b.isBordered = false
            b.contentTintColor = .white
            b.target = self
            b.action = action
            b.toolTip = tip
            controls.addSubview(b)
        }
        style(pinButton, "pin.fill", #selector(togglePin), "固定/取消固定")
        style(closeButton, "xmark", #selector(close), "隐藏")
        setPinned(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func layout() {
        super.layout()
        let cw: CGFloat = 58, ch: CGFloat = 24
        controls.frame = NSRect(x: (bounds.width - cw) / 2, y: bounds.height - ch - 4, width: cw, height: ch)
        pinButton.frame = NSRect(x: 3, y: 2, width: 25, height: 20)
        closeButton.frame = NSRect(x: 30, y: 2, width: 25, height: 20)
    }

    /// Pinned = click-through + lock position/size, with the controls hidden.
    /// Un-pin from the menu bar menu (「固定悬浮灯」).
    func setPinned(_ p: Bool) {
        pinned = p
        panel?.ignoresMouseEvents = p
        panel?.isMovableByWindowBackground = !p
        hovering = false
        controls.isHidden = true
        updatePinImage()
        needsDisplay = true
    }

    private func updatePinImage() {
        let sym = pinned ? "pin.slash.fill" : "pin.fill"
        pinButton.image = NSImage(systemSymbolName: sym, accessibilityDescription: "固定/取消固定")
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        if !pinned { controls.isHidden = false }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        controls.isHidden = true
        needsDisplay = true
    }

    @objc private func togglePin() { onTogglePin?() }
    @objc private func close() { onClose?() }

    // Corner resize (bottom-right), avoids SwiftUI drag jitter.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !pinned, p.x > bounds.maxX - 16, p.y < bounds.minY + 16 {
            resizing = true
            resizeStart = event.locationInWindow
            startFrame = panel?.frame ?? .zero
            return
        }
        super.mouseDown(with: event)  // falls through to isMovableByWindowBackground
    }
    override func mouseDragged(with event: NSEvent) {
        guard resizing, let panel else { return super.mouseDragged(with: event) }
        let dx = event.locationInWindow.x - resizeStart.x
        let dy = event.locationInWindow.y - resizeStart.y
        var f = startFrame
        f.size.width = max(34, startFrame.width + dx)
        f.size.height = max(90, startFrame.height - dy)
        f.origin.y = startFrame.maxY - f.height
        panel.setFrame(f, display: true)
    }
    override func mouseUp(with event: NSEvent) {
        resizing = false
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // ⌥ + scroll adjusts opacity; plain scroll resizes (top-left anchored).
        if event.modifierFlags.contains(.option) {
            onOpacityDelta?(event.scrollingDeltaY)
            return
        }
        guard !pinned, let panel else { return super.scrollWheel(with: event) }
        let factor = 1 + event.scrollingDeltaY * 0.01
        var f = panel.frame
        let newW = max(34, min(500, f.width * factor))
        let newH = max(90, min(1400, f.height * factor))
        f.origin.y += f.height - newH
        f.size = NSSize(width: newW, height: newH)
        panel.setFrame(f, display: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering && !pinned else { return }
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath()
        let bx = bounds.maxX - 4, by = bounds.minY + 4
        for o in stride(from: 0, through: 8, by: 4) {
            path.move(to: NSPoint(x: bx - CGFloat(o), y: by))
            path.line(to: NSPoint(x: bx, y: by + CGFloat(o)))
        }
        path.lineWidth = 1
        path.stroke()
    }
}
// MARK: - Panel & controller

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FloatingLightController: NSObject, ObservableObject {
    let settings = FloatingSettings()
    private let state: AppState
    private var panels: [FloatingPanel] = []

    init(state: AppState) {
        self.state = state
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        sync()
    }

    @objc private func screensChanged() { sync() }

    var pinned: Bool { settings.pinned }
    func toggleVisible() { settings.visible.toggle(); sync() }
    func togglePin() { settings.pinned.toggle(); sync() }
    func setAllScreens(_ on: Bool) { settings.allScreens = on; sync() }
    func setOpacity(_ v: Double) { settings.opacity = min(1, max(0.2, v)) }

    func sync() {
        if !settings.visible { tearDown(); return }
        let screens = settings.allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        if panels.count != screens.count {
            tearDown()
            for (i, screen) in screens.enumerated() {
                panels.append(makePanel(screen: screen, index: i))
            }
        }
        for p in panels {
            (p.contentView as? FloatingRootView)?.setPinned(settings.pinned)
            p.orderFrontRegardless()
        }
    }

    private func tearDown() {
        for p in panels { p.orderOut(nil); p.close() }
        panels.removeAll()
    }

    private func makePanel(screen: NSScreen, index: Int) -> FloatingPanel {
        let d = UserDefaults.standard
        let size = NSSize(width: d.object(forKey: "floating.w") as? Double ?? 60,
                          height: d.object(forKey: "floating.h") as? Double ?? 180)
        let v = screen.visibleFrame
        let defaultRect = NSRect(x: v.maxX - size.width - 16, y: v.maxY - size.height - 16,
                                 width: size.width, height: size.height)

        let panel = FloatingPanel(contentRect: defaultRect,
                                  styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                  backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true

        let host = NSHostingView(rootView: FloatingLamps(state: state, settings: settings))
        let root = FloatingRootView(hosting: host)
        root.panel = panel
        root.onTogglePin = { [weak self] in self?.togglePin() }
        root.onClose = { [weak self] in
            self?.settings.visible = false
            self?.sync()
        }
        root.onOpacityDelta = { [weak self] d in
            guard let self else { return }
            self.settings.opacity = min(1, max(0.2, self.settings.opacity + Double(d) * 0.02))
        }
        root.setPinned(settings.pinned)
        panel.contentView = root

        let name = "AIStatusFloat-\(index)"
        panel.setFrameAutosaveName(name)
        if !panel.setFrameUsingName(name) {
            panel.setFrame(defaultRect, display: false)
        }
        return panel
    }
}

