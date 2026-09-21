import AppKit
import SwiftUI

/// Floating panel shown via the global hot key — an entry point that works even
/// when the menu bar item is hidden under the notch.
struct PanelView: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: FloatingSettings
    var onDemo: () -> Void
    var onClear: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let lv = Pattern.levels(state.mode, t)
                let color = StatusIcon.blendedColor(r: lv.r, y: lv.y, g: lv.g)
                let light = StatusIcon.lighten(color, 0.45)
                let alpha = StatusIcon.intensity(r: lv.r, y: lv.y, g: lv.g)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(gradient: Gradient(colors: [Color(nsColor: light), Color(nsColor: color)]),
                                                 center: UnitPoint(x: 0.32, y: 0.30),
                                                 startRadius: 0, endRadius: 28))
                        Ellipse()
                            .fill(Color.white)
                            .frame(width: 15, height: 10)
                            .offset(x: -9, y: -12)
                            .opacity(0.55 * alpha)
                    }
                    .frame(width: 40, height: 40)
                    .opacity(max(0.22, alpha))
                    .shadow(color: Color(nsColor: color).opacity(alpha > 0.55 ? 0.45 : 0), radius: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.contract.label(state.mode) + (state.manual ? " · 手动" : ""))
                            .font(.headline)
                        Text(state.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if !state.sessions.isEmpty {
                ForEach(state.sessions.prefix(6), id: \.sessionId) { s in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: state.contract.colorHex(state.contract.mode(for: s.state)))))
                            .frame(width: 8, height: 8)
                        Text(s.name ?? s.agent).font(.caption)
                        Text("— \(s.state)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Text("悬浮灯透明度").font(.caption)
                Slider(value: $settings.opacity, in: 0.2...1.0)
                Text("\(Int(settings.opacity * 100))%")
                    .font(.caption).monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }

            HStack {
                Button("演示", action: onDemo)
                Button("清空", action: onClear)
                Spacer()
                Button("退出", action: onQuit)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

final class PanelController {
    private var window: NSWindow?
    private let state: AppState
    private let settings: FloatingSettings
    private let onDemo: () -> Void
    private let onClear: () -> Void
    private let onQuit: () -> Void

    init(state: AppState,
         settings: FloatingSettings,
         onDemo: @escaping () -> Void,
         onClear: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.state = state
        self.settings = settings
        self.onDemo = onDemo
        self.onClear = onClear
        self.onQuit = onQuit
    }

    func toggle() {
        if let w = window, w.isVisible {
            w.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: PanelView(state: state,
                                                         settings: settings,
                                                         onDemo: onDemo,
                                                         onClear: onClear,
                                                         onQuit: onQuit))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "AI Status Light"
            w.isReleasedWhenClosed = false
            w.contentView = host
            window = w
        }
        if let host = window?.contentView {
            let fit = host.fittingSize
            let w = (fit.width.isFinite && fit.width > 200) ? min(max(340, fit.width), 520) : 360
            let h = (fit.height.isFinite && fit.height > 120) ? min(fit.height, 720) : 420
            window?.setContentSize(NSSize(width: w, height: h))
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
