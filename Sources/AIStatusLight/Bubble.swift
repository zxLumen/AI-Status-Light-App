import AppKit
import SwiftUI

/// A small transient card shown just below the menu bar item when a task
/// changes to a key state (needs-you / done / error). Non-activating, fades
/// away on its own; clicking it jumps to the task app. Dragging it or a
/// trackpad two-finger swipe pushes it away *without* acknowledging — the
/// session stays pending and the light keeps showing.
struct BubbleView: View {
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
/// the total to the controller once the gesture settles.
final class BubbleContainerView: FirstMouseView {
    var onScrollChanged: ((CGFloat) -> Void)?
    var onScrollSettled: ((CGFloat) -> Void)?
    private var accum: CGFloat = 0
    private var settle: Timer?

    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy), abs(dx) > 0.1 else { return }   // ignore vertical scrolls

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
    private var hideTimer: Timer?
    private var onClick: (() -> Void)?
    private var origin: NSPoint = .zero
    private var autoHide: Double = 8
    private var dragging = false
    private var hovering = false

    private static let swipeDistance: CGFloat = 60    // two-finger swipe
    private static let dragDistance: CGFloat = 80     // mouse drag

    func show(label: String, colorHex: String, session: String, agent: String,
              detail: String? = nil, canJump: Bool, duration: Double, anchor: NSRect?,
              onClick: @escaping () -> Void) {
        dismiss()
        self.onClick = onClick
        self.autoHide = max(1, duration)

        let view = BubbleView(label: label, colorHex: colorHex, session: session,
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
                                  self.panel?.setFrameOrigin(NSPoint(x: self.origin.x + dx,
                                                                     y: self.origin.y))
                              },
                              onDragEnded: { [weak self] dx, predicted in
                                  guard let self else { return }
                                  self.dragging = false
                                  let signed = dx != 0 ? dx : predicted
                                  if abs(dx) > Self.dragDistance || abs(predicted) > Self.dragDistance * 2 {
                                      self.fling(direction: signed < 0 ? -1 : 1)
                                  } else {
                                      self.snapBack()
                                  }
                              })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize

        let panel = BubblePanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        let container = BubbleContainerView(frame: NSRect(origin: .zero, size: size))
        container.onScrollChanged = { [weak self] _ in self?.pauseAutoHide() }
        container.onScrollSettled = { [weak self] total in
            guard let self else { return }
            if abs(total) > Self.swipeDistance {
                self.fling(direction: total < 0 ? -1 : 1)
            } else if !self.hovering {
                self.resumeAutoHide()
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
        var origin: NSPoint
        if let a = anchor {
            origin = NSPoint(x: a.midX - size.width / 2, y: a.minY - size.height - 6)
        } else {
            origin = NSPoint(x: vis.maxX - size.width - 16, y: vis.maxY - size.height - 40)
        }
        origin.x = min(max(vis.minX + 8, origin.x), vis.maxX - size.width - 8)
        self.origin = origin
        panel.setFrame(NSRect(origin: origin, size: size), display: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
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
        guard let panel else { return }
        self.panel = nil
        var target = panel.frame
        if let dir = direction {
            let screen = NSScreen.screens.first { $0.frame.contains(origin) }
                ?? NSScreen.main ?? NSScreen.screens.first
            let width = screen?.frame.width ?? 1400
            target.origin.x = origin.x + dir * (width + panel.frame.width)
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func fling(direction: CGFloat) { finish(direction: direction) }

    private func snapBack() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in
            guard let self, !self.hovering else { return }
            self.resumeAutoHide()
        })
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
