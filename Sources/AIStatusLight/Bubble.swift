import AppKit
import SwiftUI

/// A small transient card shown just below the menu bar item when a task
/// changes to a key state (needs-you / done / error). Non-activating, fades
/// away on its own; clicking it jumps to the task app.
struct BubbleView: View {
    let label: String
    let colorHex: String
    let session: String
    let agent: String
    let canJump: Bool
    var onTap: () -> Void
    var onClose: () -> Void
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
                Text(canJump ? "点击跳转" : "点击打开状态面板")
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
        .frame(width: 250, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hover = $0 }
    }
}

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click even when the panel isn't key, so tapping the bubble
/// (or its close button) works immediately instead of being swallowed.
final class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BubbleController {
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var onClick: (() -> Void)?

    func show(label: String, colorHex: String, session: String, agent: String,
              canJump: Bool, duration: Double, anchor: NSRect?, onClick: @escaping () -> Void) {
        dismiss()
        self.onClick = onClick

        let view = BubbleView(label: label, colorHex: colorHex, session: session,
                              agent: agent, canJump: canJump,
                              onTap: { [weak self] in
                                  self?.onClick?()
                                  self?.dismiss()
                              },
                              onClose: { [weak self] in self?.dismiss() })
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
        let container = FirstMouseView(frame: NSRect(origin: .zero, size: size))
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
        panel.setFrame(NSRect(origin: origin, size: size), display: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTimer = Timer.scheduledTimer(withTimeInterval: max(1, duration), repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        onClick = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
