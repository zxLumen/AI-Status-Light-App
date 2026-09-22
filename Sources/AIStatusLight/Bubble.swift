import AppKit
import SwiftUI

/// Drives the card's live offset/opacity so gestures and the dismiss animation
/// run on SwiftUI's (GPU-backed) layer instead of animating the window frame.
final class BubbleModel: ObservableObject {
    @Published var offset: CGFloat = 0
    @Published var opacity: Double = 1
}

/// A small transient card shown just below the menu bar item when a task
/// changes to a key state (needs-you / done / error). Non-activating, fades
/// away on its own; clicking it jumps to the task app. Dragging it or a
/// trackpad two-finger swipe pushes it away *without* acknowledging — the
/// session stays pending and the light keeps showing.
struct BubbleView: View {
    @ObservedObject var model: BubbleModel
    let label: String
    let colorHex: String
    let session: String
    let agent: String
    let detail: String?
    let canJump: Bool
    var onTap: () -> Void
    var onClose: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: colorHex)))
                .frame(width: 12, height: 12)
                .shadow(color: Color(nsColor: NSColor(hex: colorHex)).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13, weight: .semibold))
                Text("\(agent) · \(session)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(canJump ? "点击跳转 · 双指滑动关闭" : "点击打开状态面板 · 双指滑动关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            if hover {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 270, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .offset(x: model.offset)
        .opacity(model.opacity)
        .onTapGesture { onTap() }
        .onHover { hover = $0; onHoverChange($0) }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in onDragChanged(v.translation.width) }
                .onEnded { v in
                    onDragEnded(v.translation.width, v.predictedEndTranslation.width)
                }
        )
    }
}

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click even when the panel isn't key, so tapping the bubble
/// (or its close button) works immediately instead of being swallowed.
class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Trackpad-friendly container: a two-finger horizontal swipe arrives as
/// `scrollWheel` events (not a mouse drag), so accumulate them here and hand
/// the total to the controller once the gesture settles. The panel is padded
/// with transparent margins so the card can slide as it follows the gesture;
/// hit-testing is limited to the card so the empty margins don't eat clicks.
final class BubbleContainerView: FirstMouseView {
    var margin: CGFloat = 0
    var offsetProvider: () -> CGFloat = { 0 }
    var onScrollChanged: ((CGFloat) -> Void)?
    var onScrollSettled: ((CGFloat) -> Void)?
    private var accum: CGFloat = 0
    private var settle: Timer?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        var r = bounds.insetBy(dx: margin, dy: 0)
        r.origin.x += offsetProvider()
        guard r.contains(p) else { return nil }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy), abs(dx) > 0.1 else {
            super.scrollWheel(with: event)     // let vertical scroll through
            return
        }
        accum += dx
        onScrollChanged?(accum)
        settle?.invalidate()
        let t = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            let total = self.accum
            self.accum = 0
            self.onScrollSettled?(total)
        }
        RunLoop.main.add(t, forMode: .common)
        settle = t
    }
}

final class BubbleController {
    private var panel: NSPanel?
    private var model: BubbleModel?
    private var hideTimer: Timer?
    private var onClick: (() -> Void)?
    private var autoHide: Double = 8
    private var dragging = false
    private var hovering = false
    private var cardWidth: CGFloat = 270
    private var showToken = 0

    private static let swipeDistance: CGFloat = 60    // two-finger swipe
    private static let dragDistance: CGFloat = 80     // mouse drag
    private static let margin: CGFloat = 60           // transparent side padding
    private static let followRatio: CGFloat = 0.45    // live-follow while swiping
    private static let followLimit: CGFloat = 45

    func show(label: String, colorHex: String, session: String, agent: String,
              detail: String? = nil, canJump: Bool, duration: Double, anchor: NSRect?,
              onClick: @escaping () -> Void) {
        dismiss()
        showToken += 1
        self.onClick = onClick
        self.autoHide = max(1, duration)
        self.dragging = false
        self.hovering = false

        let model = BubbleModel()
        self.model = model
        let view = BubbleView(model: model, label: label, colorHex: colorHex, session: session,
                              agent: agent, detail: detail, canJump: canJump,
                              onTap: { [weak self] in
                                  self?.onClick?()
                                  self?.dismiss()
                              },
                              onClose: { [weak self] in self?.dismiss() },
                              onHoverChange: { [weak self] inside in
                                  guard let self else { return }
                                  self.hovering = inside
                                  if inside {
                                      self.pauseAutoHide()
                                  } else if !self.dragging {
                                      self.resumeAutoHide()
                                  }
                              },
                              onDragChanged: { [weak self] dx in
                                  guard let self else { return }
                                  self.dragging = true
                                  self.pauseAutoHide()
                                  self.model?.offset = dx        // 1:1 follow
                              },
                              onDragEnded: { [weak self] dx, predicted in
                                  guard let self else { return }
                                  self.dragging = false
                                  let signed = dx != 0 ? dx : predicted
                                  if abs(dx) > Self.dragDistance || abs(predicted) > Self.dragDistance * 2 {
                                      self.fling(direction: signed < 0 ? -1 : 1)
                                  } else {
                                      self.snapBack(resume: !self.hovering)
                                  }
                              })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        self.cardWidth = size.width
        let panelSize = NSSize(width: size.width + Self.margin * 2, height: size.height)

        let panel = BubblePanel(contentRect: NSRect(origin: .zero, size: panelSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        let container = BubbleContainerView(frame: NSRect(origin: .zero, size: panelSize))
        container.margin = Self.margin
        container.offsetProvider = { [weak model] in model?.offset ?? 0 }
        container.onScrollChanged = { [weak self] accum in
            guard let self else { return }
            self.pauseAutoHide()
            let v = max(-Self.followLimit, min(Self.followLimit, accum * Self.followRatio))
            self.model?.offset = v
        }
        container.onScrollSettled = { [weak self] total in
            guard let self else { return }
            if abs(total) > Self.swipeDistance {
                self.fling(direction: total < 0 ? -1 : 1)
            } else {
                self.snapBack(resume: !self.hovering)
            }
        }
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        let screen = (anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.contains(rect.origin) }
        }) ?? NSScreen.main ?? NSScreen.screens.first
        let vis = screen?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var cardOrigin: NSPoint
        if let a = anchor {
            cardOrigin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 6)
        } else {
            cardOrigin = NSPoint(x: vis.maxX - size.width - 16, y: vis.maxY - size.height - 40)
        }
        cardOrigin.x = min(max(vis.minX + 8, cardOrigin.x), vis.maxX - size.width - 8)
        let panelOrigin = NSPoint(x: cardOrigin.x - Self.margin, y: cardOrigin.y)
        panel.setFrame(NSRect(origin: panelOrigin, size: panelSize), display: false)

        panel.alphaValue = 1
        model.opacity = 0
        panel.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.15)) { model.opacity = 1 }
        self.panel = panel
        resumeAutoHide()
    }

    func dismiss() { finish(direction: nil) }

    /// Close the card without acknowledging: the session stays pending and the
    /// light keeps showing until the user jumps to it or focuses its window.
    private func finish(direction: CGFloat?) {
        hideTimer?.invalidate()
        hideTimer = nil
        onClick = nil
        dragging = false
        hovering = false
        guard let model, let panel else { return }
        self.panel = nil
        self.model = nil
        let token = showToken
        if let dir = direction {
            withAnimation(.easeOut(duration: 0.18)) {
                model.offset = dir * (cardWidth + Self.margin + 20)
                model.opacity = 0
            }
        } else {
            withAnimation(.easeIn(duration: 0.15)) { model.opacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak panel] in
            guard token == self.showToken else { return }
            panel?.orderOut(nil)
        }
    }

    private func fling(direction: CGFloat) { finish(direction: direction) }

    private func snapBack(resume: Bool) {
        guard let model else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { model.offset = 0 }
        if resume { resumeAutoHide() }
    }

    private func pauseAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func resumeAutoHide() {
        pauseAutoHide()
        guard panel != nil else { return }
        let t = Timer(timeInterval: autoHide, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
        RunLoop.main.add(t, forMode: .common)
        hideTimer = t
    }
}
