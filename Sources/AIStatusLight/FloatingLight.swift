import AppKit
import SwiftUI

// MARK: - Settings (persisted)

final class FloatingSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var visible: Bool { didSet { d.set(visible, forKey: "floating.visible") } }
    @Published var pinned: Bool { didSet { d.set(pinned, forKey: "floating.pinned") } }
    @Published var allScreens: Bool { didSet { d.set(allScreens, forKey: "floating.allScreens") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "floating.opacity") } }
    @Published var shell: Bool { didSet { d.set(shell, forKey: "floating.shell") } }
    @Published var hoverFade: Bool { didSet { d.set(hoverFade, forKey: "floating.hoverFade") } }
    @Published var hoverOpacity: Double { didSet { d.set(hoverOpacity, forKey: "floating.hoverOpacity") } }
    @Published var hovered: Bool = false          // transient: cursor over the light

    /// Opacity actually rendered: the base setting, faded out while the cursor
    /// is over the light (when "hover to fade" is enabled).
    var renderOpacity: Double {
        FloatingSettings.effectiveOpacity(base: opacity, hovered: hovered,
                                          hoverFade: hoverFade, hoverOpacity: hoverOpacity)
    }

    static func effectiveOpacity(base: Double, hovered: Bool,
                                 hoverFade: Bool, hoverOpacity: Double) -> Double {
        base * (hovered && hoverFade ? hoverOpacity : 1)
    }

    init() {
        visible = d.object(forKey: "floating.visible") as? Bool ?? true
        pinned = d.object(forKey: "floating.pinned") as? Bool ?? false
        allScreens = d.object(forKey: "floating.allScreens") as? Bool ?? false
        opacity = d.object(forKey: "floating.opacity") as? Double ?? 1.0
        shell = d.object(forKey: "floating.shell") as? Bool ?? false
        hoverFade = d.object(forKey: "floating.hoverFade") as? Bool ?? true
        hoverOpacity = d.object(forKey: "floating.hoverOpacity") as? Double ?? 0.15
    }
}

// MARK: - Lamps (three glossy orbs, vertical, transparent)

struct FloatingLamps: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: FloatingSettings

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shell = settings.shell
            let glow: CGFloat = 1.35                       // cell = glow room around the lamp
            let dShell = min(w / 1.62, h / 4.698)
            let dPlain = min(w / glow, h / (3 * glow))
            let d = max(5, shell ? dShell : dPlain)
            let cell = d * glow
            let margin = shell ? cell * 0.10 : 0
            let gap = shell ? cell * 0.14 : 0
            let colW = shell ? cell + margin * 2 : w
            let colH = shell ? cell * 3 + gap * 2 + margin * 2 : h
            let spacing = shell ? gap : (h - cell * 3) / 4
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let lv = Pattern.levels(state.mode, t)
                VStack(spacing: spacing) {
                    lamp(lv.r, StatusIcon.red, d, cell)
                    lamp(lv.y, StatusIcon.yellow, d, cell)
                    lamp(lv.g, StatusIcon.green, d, cell)
                }
                .frame(width: colW, height: colH)
                .background(housing(corner: min(colW, colH) * 0.18))
            }
            .frame(width: w, height: h)
        }
        .opacity(settings.renderOpacity)
        .animation(.easeInOut(duration: 0.12), value: settings.hovered)
        .allowsHitTesting(false)
    }

    /// Optional rounded "traffic light" housing behind the lamps. Drawn as a
    /// static background (outside the animation) so it doesn't add per-frame cost.
    @ViewBuilder
    private func housing(corner: CGFloat) -> some View {
        if settings.shell {
            let r = max(10, min(corner, 32))
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
                )
                .padding(2)
                .shadow(color: .black.opacity(0.35), radius: 7, y: 2)
        }
    }

    /// One stable view tree per lamp (no `if` branch) so the lit/unlit transition
    /// never swaps subtrees each frame — that was causing the stutter. Brightness
    /// is expressed through colour + opacity; the glow is a gradient layer instead
    /// of `.shadow` (no offscreen rendering).
    private func lamp(_ level: Double, _ color: NSColor, _ d: CGFloat, _ cell: CGFloat) -> some View {
        let on = CGFloat(max(0, min(1, level)))
        let housing = NSColor(white: 0.26, alpha: 1)
        let body = housing.blended(withFraction: on, of: color) ?? color
        let light = StatusIcon.lighten(body, 0.22)
        return ZStack {
            // glow, contained inside `cell` (fades to 0 at the edge → no clipping)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(nsColor: color).opacity(0.55 * on),
                             Color(nsColor: color).opacity(0)],
                    center: .center, startRadius: d * 0.5, endRadius: cell * 0.5))
                .frame(width: cell, height: cell)
            if settings.shell {
                // recessed lamp socket
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.03), Color(white: 0.17)],
                                         center: .center, startRadius: d * 0.12, endRadius: d * 0.70))
                    .frame(width: d * 1.30, height: d * 1.30)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55),
                                                   lineWidth: max(0.8, d * 0.05)))
            }
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
        .frame(width: cell, height: cell)
        .opacity(0.5 + 0.5 * Double(on))
    }
}

// MARK: - Root NSView: hover controls, background drag, corner resize, scroll zoom

final class FloatingRootView: NSView {
    weak var panel: NSPanel?
    var onTogglePin: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpacityDelta: ((CGFloat) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var aspectRatio: CGFloat?          // when set, resize is locked to this w/h
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        if hovering { onHoverChange?(false) }
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
        onHoverChange?(true)
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        controls.isHidden = true
        onHoverChange?(false)
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
        let dy = event.locationInWindow.y - resizeStart.y
        var f = startFrame
        if let ar = aspectRatio {
            let newH = max(120, startFrame.height - dy)
            f.size = NSSize(width: newH * ar, height: newH)
        } else {
            let dx = event.locationInWindow.x - resizeStart.x
            f.size.width = max(34, startFrame.width + dx)
            f.size.height = max(90, startFrame.height - dy)
        }
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
        let newH = max(90, min(1400, f.height * factor))
        let newW = aspectRatio.map { newH * $0 } ?? max(34, min(500, f.width * factor))
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
    private var globalMonitor: Any?

    init(state: AppState) {
        self.state = state
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        sync()
    }

    @objc private func screensChanged() { sync() }

    var pinned: Bool { settings.pinned }
    static let shellAspect: CGFloat = 1.56 / 4.524   // w/h of the snug lamp column

    func toggleVisible() { settings.visible.toggle(); sync() }
    func togglePin() { settings.pinned.toggle(); sync() }
    func setAllScreens(_ on: Bool) { settings.allScreens = on; sync() }
    func setOpacity(_ v: Double) { settings.opacity = min(1, max(0.2, v)) }
    func setShell(_ on: Bool) { settings.shell = on; sync() }
    func setHoverFade(_ on: Bool) { settings.hoverFade = on; sync() }
    func setHoverOpacity(_ v: Double) { settings.hoverOpacity = min(1, max(0, v)) }

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
            if let root = p.contentView as? FloatingRootView {
                root.setPinned(settings.pinned)
                root.aspectRatio = settings.shell ? Self.shellAspect : nil
                if settings.shell {
                    var f = p.frame
                    let newW = f.height * Self.shellAspect
                    if abs(newW - f.width) > 0.5 {
                        f.size.width = newW
                        p.setFrame(f, display: true)
                    }
                }
            }
            p.orderFrontRegardless()
        }
        updateHoverMonitor()
    }

    /// While pinned the panel ignores mouse events, so `mouseEntered/Exited`
    /// never fire — watch the cursor globally and fade the light when it is
    /// over one of the panels.
    private func updateHoverMonitor() {
        let need = settings.visible && settings.pinned && settings.hoverFade && !panels.isEmpty
        if need, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.evaluateHover()
            }
        } else if !need, let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
            setHovered(false)
        }
    }

    private func evaluateHover() {
        let p = NSEvent.mouseLocation
        let inside = panels.contains { $0.frame.contains(p) }
        if inside != settings.hovered { setHovered(inside) }
    }

    private func setHovered(_ v: Bool) {
        guard settings.hovered != v else { return }
        if ProcessInfo.processInfo.environment["AISTATUS_DEBUG"] != nil {
            FileHandle.standardError.write("floating hover=\(v) pinned=\(settings.pinned)\n".data(using: .utf8)!)
        }
        withAnimation(.easeInOut(duration: 0.12)) { settings.hovered = v }
    }

    private func tearDown() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        setHovered(false)
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
        root.onHoverChange = { [weak self] inside in self?.setHovered(inside) }
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

