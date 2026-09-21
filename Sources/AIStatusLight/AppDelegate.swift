import AppKit
import ServiceManagement
import Carbon.HIToolbox
import PrivateStatusItem

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let contract = Contract.load()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var appState: AppState!
    private var panel: PanelController!
    private var hotKey: HotKey?

    private var last = Aggregate(mode: "idle", state: "idle", reason: "starting",
                                 sessions: [], manual: false)
    private var pollTimer: Timer?
    private var animTimer: Timer?
    private var animEpoch = Date()
    private var demoStart: Date?
    private var demoUntil: Date?
    private let debug = ProcessInfo.processInfo.environment["AISTATUS_DEBUG"] != nil

    private func dbg(_ s: String) {
        if debug { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState(contract: contract)

        let env = ProcessInfo.processInfo.environment
        // The private priority API turned out unreliable on macOS 15 (it can place
        // the item off-screen left), so it is opt-in for experiments only.
        if env["AISTATUS_PRIVATE"] != nil,
           let item = AIStatusItemWithPriority(NSStatusItem.variableLength, Int32.min) {
            statusItem = item
            dbg("status item: private priority API")
        } else {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            dbg("status item: public API")
        }
        if env["AISTATUS_NO_AUTOSAVE"] == nil {
            statusItem.autosaveName = "com.zxlumen.aistatus"
        }
        statusItem.button?.image = StatusIcon.image(r: 0.1, y: 0.1, g: 0.1)

        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        panel = PanelController(
            state: appState,
            onDemo: { [weak self] in self?.startDemo() },
            onClear: { [weak self] in self?.clearState() },
            onOpen: { [weak self] in self?.openPanel() },
            onQuit: { NSApp.terminate(nil) })
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L),
                        modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.panel.toggle()
        }
        if hotKey == nil { dbg("hot key registration failed") }

        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        if debug {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, let btn = self.statusItem.button, let scr = NSScreen.main else { return }
                let onScreen = btn.window?.convertToScreen(btn.convert(btn.bounds, to: nil)) ?? .zero
                let left = scr.auxiliaryTopLeftArea ?? .zero
                let right = scr.auxiliaryTopRightArea ?? .zero
                self.dbg("item.onScreen=\(onScreen)")
                self.dbg("notch: leftArea=\(left) rightArea=\(right) → notch spans ~\(left.maxX)...\(right.minX)")
                self.dbg("visible=\(self.statusItem.isVisible) hiddenByNotch=\(onScreen.maxX > left.maxX && onScreen.minX < right.minX)")
                self.dbg("screenWidth=\(scr.frame.width)")
            }
        }
    }

    // MARK: - State

    private func currentMode() -> String {
        if let until = demoUntil, Date() < until, let start = demoStart {
            let seq = ["thinking", "working", "busy", "success", "blocked", "error", "traffic"]
            return seq[Int(Date().timeIntervalSince(start) / 1.2) % seq.count]
        }
        return last.mode
    }

    private func poll() {
        last = Aggregator.aggregate(StateStore.readSessions(), contract: contract)
        appState?.update(last)
        syncAnimation()
    }

    private func refreshIcon() {
        let t = Date().timeIntervalSince(animEpoch)
        let lv = Pattern.levels(currentMode(), t)
        statusItem.button?.image = StatusIcon.image(r: lv.r, y: lv.y, g: lv.g)
    }

    private func syncAnimation() {
        if Pattern.isAnimated(currentMode()) {
            if animTimer == nil {
                animEpoch = Date()
                let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                    self?.refreshIcon()
                }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate()
            animTimer = nil
            refreshIcon()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mode = currentMode()

        menu.addItem(disabled(line(contract.colorHex(mode),
                                   contract.label(mode) + (last.manual ? " · 手动" : ""))))
        menu.addItem(disabled(gray(last.reason)))
        menu.addItem(.separator())

        if last.sessions.isEmpty {
            menu.addItem(disabled(gray("无活跃会话")))
        } else {
            for rec in last.sessions.sorted(by: { contract.priorityOf($0.state) > contract.priorityOf($1.state) }).prefix(8) {
                let color = contract.colorHex(contract.mode(for: rec.state))
                let label = (rec.name?.isEmpty == false ? rec.name! : rec.agent)
                menu.addItem(disabled(line(color, "\(label) — \(rec.state)")))
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("演示(Demo)", #selector(startDemo)))
        menu.addItem(action("清空状态", #selector(clearState)))
        menu.addItem(action("打开控制面板", #selector(openPanel)))
        let login = action("开机自启", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("退出", #selector(quit), key: "q"))
    }

    private func line(_ hex: String, _ text: String) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor(hex: hex)]))
        s.append(NSAttributedString(string: " " + text))
        return s
    }

    private func gray(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }

    private func disabled(_ attr: NSAttributedString) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = attr
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func startDemo() {
        demoStart = Date()
        demoUntil = Date().addingTimeInterval(12)
        syncAnimation()
    }

    @objc private func clearState() {
        StateStore.clear()
        poll()
    }

    @objc private func openPanel() {
        if let url = URL(string: "http://127.0.0.1:8377") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        LoginItem.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
