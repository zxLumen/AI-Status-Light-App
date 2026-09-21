import AppKit
import ServiceManagement
import PrivateStatusItem

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let contract = Contract.load()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var appState: AppState!
    private var panel: PanelController!
    private var floating: FloatingLightController!
    private let bubble = BubbleController()
    private var prevMode: String?
    private var lastBubbleAt = Date.distantPast
    private var interruptNotified: Set<String> = []
    private var errorTimes: [Date] = []
    private var alarmAt = Date.distantPast

    private var last = Aggregate(mode: "idle", state: "idle", reason: "starting",
                                 sessions: [], manual: false)
    private var allSessions: [SessionRecord] = []
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

        floating = FloatingLightController(state: appState)

        panel = PanelController(
            state: appState,
            settings: floating.settings,
            onDemo: { [weak self] in self?.startDemo() },
            onClear: { [weak self] in self?.clearState() },
            onQuit: { NSApp.terminate(nil) })
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
        let records = StateStore.readSessions()
        allSessions = records
        last = Aggregator.aggregate(records, contract: contract)
        appState?.update(last)
        syncAnimation()
        trackInterrupts(records)
        maybeBubble()
    }

    private func bubbleEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: "ui.bubble.\(key)") as? Bool ?? (key != "interrupt")
    }

    /// Show a menu bar bubble when the aggregate settles into a key state.
    private func maybeBubble() {
        let mode = last.mode
        defer { prevMode = mode }
        guard let prev = prevMode, mode != prev else { return }
        guard ["blocked", "success", "error"].contains(mode) else { return }
        let d = UserDefaults.standard
        guard d.object(forKey: "ui.bubble") as? Bool ?? true else { return }
        guard Date().timeIntervalSince(lastBubbleAt) > 3 else { return }

        // Error escalation: repeated failures turn into an alarm.
        var shownMode = mode
        if mode == "error", bubbleEnabled("error") {
            let now = Date()
            errorTimes.append(now)
            errorTimes = errorTimes.filter { now.timeIntervalSince($0) < 120 }
            if errorTimes.count >= 2, now.timeIntervalSince(alarmAt) > 30 {
                alarmAt = now
                shownMode = "alarm"
                StateStore.setOverride(mode: "alarm", ttl: 30)   // escalate the light too
            }
        }
        let key = shownMode == "alarm" ? "error" : mode
        guard bubbleEnabled(key) else { return }
        lastBubbleAt = Date()

        // Merge multiple "needs you" sessions into one bubble.
        let live = last.sessions.filter { Date().timeIntervalSince1970 - $0.ts <= contract.ttl($0.state) }
        let blockedCount = live.filter { $0.state == "blocked" }.count
        let top = live.max { contract.priorityOf($0.state) < contract.priorityOf($1.state) }
        let agent = top?.agent ?? ""
        let dir = top?.dir
        let sid = top?.sessionId
        let name = (top?.name?.isEmpty == false) ? top!.name! : agent
        let label = (mode == "blocked" && blockedCount > 1) ? "\(blockedCount) 个任务需要你"
                                                            : contract.label(shownMode)
        let detail = (top?.message?.isEmpty == false) ? top!.message : nil
        let duration = d.object(forKey: "ui.bubbleDuration") as? Double ?? 8
        bubble.show(label: label,
                    colorHex: contract.colorHex(shownMode),
                    session: name,
                    agent: agent,
                    detail: detail,
                    canJump: AppLauncher.canJump(agent: agent),
                    duration: duration,
                    anchor: statusItemAnchor()) { [weak self] in
            self?.jump(agent: agent, directory: dir, sessionId: sid)
        }
    }

    /// A session that has been silent too long (no events, no heartbeat) is
    /// treated as interrupted: drop it (→ idle) and optionally bubble.
    private func trackInterrupts(_ records: [SessionRecord]) {
        let now = Date().timeIntervalSince1970
        let silence: Double = 1200   // 20 minutes
        let activeStates: Set<String> = ["working", "busy", "thinking", "blocked"]
        let present = Set(records.map { $0.sessionId })
        interruptNotified.formIntersection(present)

        for rec in records where activeStates.contains(rec.state)
            && now - rec.ts > silence && !interruptNotified.contains(rec.sessionId) {
            interruptNotified.insert(rec.sessionId)
            StateStore.clearSession(rec.sessionId)   // switch the light to idle
            if bubbleEnabled("interrupt"),
               UserDefaults.standard.object(forKey: "ui.bubble") as? Bool ?? true {
                let name = (rec.name?.isEmpty == false) ? rec.name! : rec.agent
                bubble.show(label: "已中断", colorHex: "#ff8a00",
                            session: name, agent: rec.agent,
                            detail: "超过 20 分钟无活动,进程/终端可能已关闭",
                            canJump: AppLauncher.canJump(agent: rec.agent),
                            duration: UserDefaults.standard.object(forKey: "ui.bubbleDuration") as? Double ?? 8,
                            anchor: statusItemAnchor()) { [weak self] in
                    self?.jump(agent: rec.agent, directory: rec.dir, sessionId: rec.sessionId)
                }
            }
        }
    }

    private func statusItemAnchor() -> NSRect? {
        guard let btn = statusItem.button, let win = btn.window else { return nil }
        return win.convertToScreen(btn.convert(btn.bounds, to: nil))
    }

    private func jump(agent: String, directory: String? = nil, sessionId: String? = nil) {
        _ = WindowFocuser.ensureTrusted()
        if !AppLauncher.activate(agent: agent, directory: directory, sessionId: sessionId) {
            panel.show()
        }
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

        if allSessions.isEmpty {
            menu.addItem(disabled(gray("无会话")))
        } else {
            let now = Date().timeIntervalSince1970
            for rec in allSessions.sorted(by: { $0.ts > $1.ts }) {
                let color = contract.colorHex(contract.mode(for: rec.state))
                let label = (rec.name?.isEmpty == false ? rec.name! : rec.agent)
                let fresh = now - rec.ts <= contract.ttl(rec.state)
                let item = NSMenuItem(title: "\(label) — \(rec.state)",
                                      action: #selector(jumpAgent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["agent": rec.agent, "dir": rec.dir ?? "", "sid": rec.sessionId] as NSDictionary
                var title = line(color, "\(label) — \(rec.state)")
                if !fresh {
                    let dim = NSMutableAttributedString(attributedString: title)
                    dim.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                     range: NSRange(location: 0, length: dim.length))
                    title = dim
                }
                item.attributedTitle = title
                item.toolTip = AppLauncher.canJump(agent: rec.agent) ? "点击跳到 \(rec.agent)" : "点击打开状态面板"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action("演示(Demo)", #selector(startDemo)))
        menu.addItem(action("清空状态", #selector(clearState)))
        menu.addItem(action("状态面板", #selector(showStatusPanel)))
        let login = action("开机自启", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        if !WindowFocuser.isTrusted {
            menu.addItem(action("授予辅助功能权限(精准跳窗口)", #selector(openAccessibility)))
        }

        menu.addItem(.separator())
        let fl = action("显示悬浮灯", #selector(toggleFloating))
        fl.state = floating.settings.visible ? .on : .off
        menu.addItem(fl)
        let fp = action("固定悬浮灯", #selector(toggleFloatingPin))
        fp.state = floating.settings.pinned ? .on : .off
        menu.addItem(fp)
        let sh = action("悬浮圆角外壳", #selector(toggleFloatingShell))
        sh.state = floating.settings.shell ? .on : .off
        menu.addItem(sh)
        let sub = NSMenu()
        let onlyMain = NSMenuItem(title: "仅主屏", action: #selector(showMainScreenOnly), keyEquivalent: "")
        onlyMain.target = self
        onlyMain.state = floating.settings.allScreens ? .off : .on
        let allScreens = NSMenuItem(title: "所有屏幕", action: #selector(showAllScreens), keyEquivalent: "")
        allScreens.target = self
        allScreens.state = floating.settings.allScreens ? .on : .off
        sub.addItem(onlyMain)
        sub.addItem(allScreens)
        let subItem = NSMenuItem(title: "悬浮灯显示在", action: nil, keyEquivalent: "")
        subItem.submenu = sub
        menu.addItem(subItem)

        let opSub = NSMenu()
        for pct in [100, 80, 60, 40] {
            let it = NSMenuItem(title: "\(pct)%", action: #selector(setFloatingOpacity(_:)), keyEquivalent: "")
            it.target = self
            it.tag = pct
            it.state = abs(floating.settings.opacity * 100 - Double(pct)) < 2 ? .on : .off
            opSub.addItem(it)
        }
        let opItem = NSMenuItem(title: "悬浮灯不透明度", action: nil, keyEquivalent: "")
        opItem.submenu = opSub
        menu.addItem(opItem)

        menu.addItem(.separator())
        let bu = action("状态变化气泡", #selector(toggleBubble))
        bu.state = (UserDefaults.standard.object(forKey: "ui.bubble") as? Bool ?? true) ? .on : .off
        menu.addItem(bu)

        let stateSub = NSMenu()
        for (title, key) in [("需要你", "blocked"), ("完成", "success"), ("出错", "error"), ("中断", "interrupt")] {
            let it = NSMenuItem(title: title, action: #selector(toggleBubbleState(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            it.state = bubbleEnabled(key) ? .on : .off
            stateSub.addItem(it)
        }
        let stateIt = NSMenuItem(title: "提示状态", action: nil, keyEquivalent: "")
        stateIt.submenu = stateSub
        menu.addItem(stateIt)

        let buSub = NSMenu()
        let curDur = UserDefaults.standard.object(forKey: "ui.bubbleDuration") as? Double ?? 8
        for secs in [2.0, 4.0, 8.0] {
            let it = NSMenuItem(title: "\(Int(secs))s", action: #selector(setBubbleDuration(_:)), keyEquivalent: "")
            it.target = self
            it.tag = Int(secs)
            it.state = abs(curDur - secs) < 0.1 ? .on : .off
            buSub.addItem(it)
        }
        let buIt = NSMenuItem(title: "气泡停留", action: nil, keyEquivalent: "")
        buIt.submenu = buSub
        menu.addItem(buIt)

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

    @objc private func showStatusPanel() {
        panel.toggle()
    }

    @objc private func jumpAgent(_ sender: NSMenuItem) {
        let info = sender.representedObject as? NSDictionary
        let agent = (info?["agent"] as? String) ?? ""
        let dir = (info?["dir"] as? String)
        let sid = (info?["sid"] as? String)
        jump(agent: agent, directory: (dir?.isEmpty == false) ? dir : nil, sessionId: sid)
    }

    @objc private func toggleBubble() {
        let d = UserDefaults.standard
        let on = !(d.object(forKey: "ui.bubble") as? Bool ?? true)
        d.set(on, forKey: "ui.bubble")
        dbg("bubble = \(on)")
    }

    @objc private func setBubbleDuration(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: "ui.bubbleDuration")
    }

    @objc private func toggleBubbleState(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let d = UserDefaults.standard
        let cur = d.object(forKey: "ui.bubble.\(key)") as? Bool ?? (key != "interrupt")
        d.set(!cur, forKey: "ui.bubble.\(key)")
    }

    @objc private func toggleLogin() {
        LoginItem.toggle()
    }

    @objc private func openAccessibility() {
        WindowFocuser.openSettings()
    }

    @objc private func toggleFloating() {
        floating.toggleVisible()
    }

    @objc private func toggleFloatingPin() {
        floating.togglePin()
    }

    @objc private func toggleFloatingShell() {
        floating.setShell(!floating.settings.shell)
    }

    @objc private func showMainScreenOnly() {
        floating.setAllScreens(false)
    }

    @objc private func showAllScreens() {
        floating.setAllScreens(true)
    }

    @objc private func setFloatingOpacity(_ sender: NSMenuItem) {
        floating.setOpacity(Double(sender.tag) / 100.0)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
