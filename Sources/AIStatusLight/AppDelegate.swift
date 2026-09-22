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
    private let push = PushNotifier()
    private var prevStates: [String: String] = [:]
    private var lastBubbleAt = Date.distantPast
    private var interruptNotified: Set<String> = []
    private var errorTimes: [Date] = []
    private var alarmAt = Date.distantPast
    private var pollTick = 0
    private var rotationModes: [String] = []
    private var rotCurrent: String?
    private var rotationTimer: Timer?
    private var lastDisplayed: String?
    private let rotationBase: Double = 2.5
    private let ackQueue = DispatchQueue(label: "aistatus.ack")
    private var lastFrontKey: String?

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
        if debug {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
            FileHandle.standardError.write((f.string(from: Date()) + "  " + s + "\n").data(using: .utf8)!)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("launch")
        appState = AppState(contract: contract)
        push.log = { [weak self] line in self?.appLog(line) }

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

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(focusChanged),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(focusChanged),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

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

    private func demoMode() -> String? {
        if let until = demoUntil, Date() < until, let start = demoStart {
            let seq = ["thinking", "working", "busy", "success", "blocked", "error", "traffic"]
            return seq[Int(Date().timeIntervalSince(start) / 1.2) % seq.count]
        }
        return nil
    }

    /// What the icon / floating light should show right now: demo → manual
    /// override → rotation (when several distinct states) → aggregate.
    private func displayMode() -> String {
        if let d = demoMode() { return d }
        if last.manual { return last.mode }
        if rotationModes.count > 1, let cur = rotCurrent, rotationModes.contains(cur) {
            return cur
        }
        return last.mode
    }

    private func currentMode() -> String { displayMode() }

    /// Distinct live states (priority order) that participate in rotation.
    @discardableResult
    private func recomputeRotation() -> Bool {
        let now = Date().timeIntervalSince1970
        var seen = Set<String>()
        var items: [(mode: String, pri: Int)] = []
        for rec in allSessions where rec.ack != true && now - rec.ts <= contract.ttl(rec.state) {
            let mode = contract.mode(for: rec.state)
            if seen.contains(mode) { continue }
            seen.insert(mode)
            items.append((mode, contract.priorityOf(rec.state)))
        }
        let modes = items.sorted { $0.pri > $1.pri }.map { $0.mode }
        let prev = rotationModes
        let changed = modes != prev
        rotationModes = modes
        if rotationModes.count <= 1 {
            rotCurrent = rotationModes.first
            rotationTimer?.invalidate()
            rotationTimer = nil
        } else {
            // Keep the mode currently shown even if the list re-ordered, so every
            // state gets its full dwell. Only switch if it disappeared …
            if let cur = rotCurrent, !modes.contains(cur) { rotCurrent = nil }
            // … or a brand-new urgent state appeared.
            if let first = modes.first, first == "blocked" || first == "error", !prev.contains(first) {
                rotCurrent = first
                rotationTimer?.invalidate()
                rotationTimer = nil
            }
            if rotCurrent == nil { rotCurrent = modes.first }
        }
        return changed
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard rotationModes.count > 1, demoMode() == nil, !last.manual,
              let cur = rotCurrent else { return }
        // blocked / error linger twice as long.
        let dwell = (cur == "blocked" || cur == "error") ? rotationBase * 2 : rotationBase
        let t = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let i = self.rotationModes.firstIndex(of: cur), !self.rotationModes.isEmpty {
                self.rotCurrent = self.rotationModes[(i + 1) % self.rotationModes.count]
            }
            self.applyDisplay(force: true)
            self.scheduleRotation()
        }
        RunLoop.main.add(t, forMode: .common)
        rotationTimer = t
    }

    private func applyDisplay(force: Bool = false) {
        let m = displayMode()
        if !force && m == lastDisplayed { return }
        lastDisplayed = m
        if appState?.mode != m { appState?.mode = m }
        dbg("display -> \(m) rotate=\(rotationModes) cur=\(rotCurrent ?? "-")")
        syncAnimation()
    }

    private func poll() {
        let records = StateStore.readSessions()
        allSessions = records
        last = Aggregator.aggregate(records, contract: contract)
        appState?.update(last)
        let changed = recomputeRotation()
        _ = changed
        applyDisplay()
        if rotationTimer == nil { scheduleRotation() }
        if let am = appState?.mode, am != displayMode() { dbg("MISMATCH appState=\(am) display=\(displayMode())") }
        trackInterrupts(records)
        pollTick &+= 1
        if pollTick % 4 == 0 { acknowledgeFocused() }
        let transitions = stateTransitions()
        maybeBubble(transitions)
        maybePush(transitions)
    }

    /// Clear a finished/failed session once its window is brought to the front.
    /// Clear a finished/failed session only when the user **switches** to its
    /// window/tab (a frontmost transition) — not merely because they're on it.
    private func acknowledgeFocused() {
        guard UserDefaults.standard.object(forKey: "ui.ackOnFocus") as? Bool ?? true else { return }
        let pending = allSessions.filter { $0.state == "success" || $0.state == "error" }
        guard !pending.isEmpty else { return }
        ackQueue.async { [weak self] in
            guard let self, let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
            let key = self.frontKey(front)
            if self.lastFrontKey == nil { self.lastFrontKey = key; return }  // prime, don't ack
            guard key != self.lastFrontKey else { return }                   // no transition
            self.lastFrontKey = key

            let matching = pending.filter {
                AppLauncher.targetBundleIds(for: $0.agent, host: $0.host).contains(front)
            }
            guard !matching.isEmpty else { return }
            let trusted = WindowFocuser.isTrusted
            var verifiedRecs: [SessionRecord] = []
            for rec in matching {
                var verified = false
                var why = ""
                if front.hasPrefix("com.microsoft.VSCode") {
                    if trusted, let title = WindowFocuser.focusedWindowTitle(bundleId: front),
                       let dir = rec.dir ?? OpenCodeDB.sessionDirectory(rec.sessionId), !dir.isEmpty {
                        let folder = (dir as NSString).lastPathComponent
                        verified = !folder.isEmpty && title.localizedCaseInsensitiveContains(folder)
                        why = "title=\"\(title)\" folder=\"\(folder)\""
                    } else {
                        // Ambiguous: only clear when this is the app's sole pending session.
                        verified = matching.count == 1
                        why = "app-level trusted=\(trusted) matching=\(matching.count) dir=\(rec.dir ?? "-")"
                    }
                } else if front == "com.googlecode.iterm2" {
                    if let r = rec.ref, !r.isEmpty, let cur = ITermFocus.currentSessionRef() {
                        verified = ITermFocus.normalize(cur) == ITermFocus.normalize(r)
                        why = "ref cur=\(cur) want=\(r) norm=\(ITermFocus.normalize(r))"
                    } else {
                        verified = matching.count == 1
                        why = "app-level ref=\(rec.ref ?? "-") matching=\(matching.count)"
                    }
                } else {
                    verified = matching.count == 1
                    why = "app-level matching=\(matching.count)"
                }
                self.appLog("ack? \(rec.sessionId) verified=\(verified) \(why)")
                if verified { verifiedRecs.append(rec) }
            }
            // Several sessions can map to the same window (same project folder) —
            // acknowledge only the most recent one per switch.
            if let one = verifiedRecs.max(by: { $0.ts < $1.ts }) {
                self.appLog("ack \(one.sessionId) state=\(one.state) host=\(one.host ?? "-") via=\(front)")
                StateStore.markAcknowledged(one.sessionId)
            }
        }
    }

    /// Identity of the current foreground window/tab (used to detect switches).
    private func frontKey(_ bundle: String) -> String {
        if bundle == "com.googlecode.iterm2" {
            return bundle + "|" + (ITermFocus.currentSessionRef() ?? "")
        }
        if bundle.hasPrefix("com.microsoft.VSCode") {
            return bundle + "|" + (WindowFocuser.focusedWindowTitle(bundleId: bundle) ?? "")
        }
        return bundle
    }


    @objc private func focusChanged() { acknowledgeFocused() }

    private func bubbleEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: "ui.bubble.\(key)") as? Bool ?? (key != "interrupt")
    }

    /// Sessions that just changed into a key state (needs-you / done / error).
    /// Fired per *session* (not the aggregate mode): with several concurrent
    /// sessions the aggregate is often a higher-priority state, so a finishing
    /// session would otherwise never be noticed. Also advances `prevStates`.
    private func stateTransitions() -> [SessionRecord] {
        var candidates: [SessionRecord] = []
        let now = Date().timeIntervalSince1970
        for rec in allSessions where rec.ack != true && now - rec.ts <= contract.ttl(rec.state) {
            if let prev = prevStates[rec.sessionId], prev != rec.state,
               ["success", "error", "blocked"].contains(rec.state) {
                candidates.append(rec)
            }
        }
        prevStates = Dictionary(allSessions.map { ($0.sessionId, $0.state) }, uniquingKeysWith: { a, _ in a })
        return candidates
    }

    /// Push the most urgent transition to the phone/watch (respects its own
    /// toggles and cooldown, independent of the bubble settings).
    private func maybePush(_ transitions: [SessionRecord]) {
        guard !transitions.isEmpty, push.isEnabled else { return }
        let badge = allSessions.filter { $0.ack != true && ($0.state == "blocked" || $0.state == "error") }.count
        for rec in push.maybeNotify(transitions, badge: badge) {
            appLog("push \(rec.state) sid=\(rec.sessionId) name=\(rec.name ?? rec.agent)")
        }
    }

    /// Show a menu bar bubble when the aggregate settles into a key state.
    private func maybeBubble(_ candidates: [SessionRecord]) {
        guard let top = candidates.max(by: { contract.priorityOf($0.state) < contract.priorityOf($1.state) })
        else { return }

        let d = UserDefaults.standard
        guard d.object(forKey: "ui.bubble") as? Bool ?? true else { return }
        guard Date().timeIntervalSince(lastBubbleAt) > 3 else { return }

        var shownState = top.state
        if top.state == "error", bubbleEnabled("error") {
            let nowD = Date()
            errorTimes.append(nowD)
            errorTimes = errorTimes.filter { nowD.timeIntervalSince($0) < 120 }
            if errorTimes.count >= 2, nowD.timeIntervalSince(alarmAt) > 30 {
                alarmAt = nowD
                shownState = "alarm"
                StateStore.setOverride(mode: "alarm", ttl: 30)   // escalate the light too
            }
        }
        let key = shownState == "alarm" ? "error" : top.state
        guard bubbleEnabled(key) else { return }
        lastBubbleAt = Date()

        let blockedCount = allSessions.filter {
            $0.state == "blocked" && $0.ack != true
                && Date().timeIntervalSince1970 - $0.ts <= contract.ttl($0.state)
        }.count
        let name = (top.name?.isEmpty == false) ? top.name! : top.agent
        let label = (top.state == "blocked" && blockedCount > 1)
            ? "\(blockedCount) 个任务需要你"
            : contract.label(shownState)
        let detail = (top.message?.isEmpty == false) ? top.message : nil
        let duration = d.object(forKey: "ui.bubbleDuration") as? Double ?? 8
        dbg("bubble \(shownState) session=\(name)")
        bubble.show(label: label,
                    colorHex: contract.colorHex(shownState),
                    session: name,
                    agent: top.agent,
                    detail: detail,
                    canJump: AppLauncher.canJump(agent: top.agent),
                    duration: duration,
                    anchor: statusItemAnchor()) { [weak self] in
            self?.jump(agent: top.agent, directory: top.dir, sessionId: top.sessionId,
                       host: top.host, ref: top.ref)
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

    private func jump(agent: String, directory: String? = nil, sessionId: String? = nil,
                      host: String? = nil, ref: String? = nil) {
        _ = WindowFocuser.ensureTrusted()
        // success/error stay until acknowledged here ("唤起"); capture state up front.
        let state = sessionId.flatMap { sid in allSessions.first { $0.sessionId == sid }?.state }
        appLog("jump agent=\(agent) host=\(host ?? "-") ref=\(ref ?? "-") dir=\(directory ?? "-")")
        // Resolve directory / run the VS Code CLI off the main thread so a slow
        // `code`/`sqlite3` can never freeze the menu bar.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = AppLauncher.activate(agent: agent, directory: directory, sessionId: sessionId,
                                          host: host, ref: ref)
            if !ok {
                DispatchQueue.main.async { self?.panel.show() }
            }
            // Acknowledged: it stays listed, but stops being an attention state.
            if let sid = sessionId, let st = state, st == "success" || st == "error" {
                StateStore.markAcknowledged(sid)
            }
        }
    }

    // MARK: - Exit diagnostics

    private func appLog(_ text: String) {
        let dir = StateStore.home
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("app.log")
        let line = ISO8601DateFormatter().string(from: Date()) + "  pid=\(getpid())  " + text + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appLog("terminate")
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
        let mode = last.mode   // menu header shows the top-priority state, not the rotating one

        menu.addItem(disabled(line(contract.colorHex(mode),
                                   contract.label(mode) + (last.manual ? " · 手动" : ""))))
        menu.addItem(disabled(gray(last.reason)))
        menu.addItem(.separator())

        if allSessions.isEmpty {
            menu.addItem(disabled(gray("无会话")))
        } else {
            let now = Date().timeIntervalSince1970
            for rec in StateStore.menuOrder(allSessions, now: now, contract: contract) {
                let color = contract.colorHex(contract.mode(for: rec.state))
                let label = (rec.name?.isEmpty == false ? rec.name! : rec.agent)
                let fresh = rec.ack != true && now - rec.ts <= contract.ttl(rec.state)
                let item = NSMenuItem(title: "\(label) — \(rec.state)",
                                      action: #selector(jumpAgent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["agent": rec.agent, "dir": rec.dir ?? "",
                                          "sid": rec.sessionId, "host": rec.host ?? "",
                                          "ref": rec.ref ?? ""] as NSDictionary
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
        let axTitle = WindowFocuser.isTrusted ? "辅助功能:已授权" : "辅助功能:未授权(点此授权)"
        menu.addItem(action(axTitle, #selector(openAccessibility)))

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
        let hf = action("悬停变透明", #selector(toggleFloatingHoverFade))
        hf.state = floating.settings.hoverFade ? .on : .off
        menu.addItem(hf)
        let hoSub = NSMenu()
        for pct in [0, 15, 30] {
            let it = NSMenuItem(title: "\(pct)%", action: #selector(setFloatingHoverOpacity(_:)), keyEquivalent: "")
            it.target = self
            it.tag = pct
            it.state = abs(floating.settings.hoverOpacity * 100 - Double(pct)) < 2 ? .on : .off
            hoSub.addItem(it)
        }
        let hoItem = NSMenuItem(title: "悬停透明度", action: nil, keyEquivalent: "")
        hoItem.submenu = hoSub
        menu.addItem(hoItem)
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

        let ack = action("切到窗口即确认", #selector(toggleAckOnFocus))
        ack.state = (UserDefaults.standard.object(forKey: "ui.ackOnFocus") as? Bool ?? true) ? .on : .off
        menu.addItem(ack)

        menu.addItem(.separator())
        let pushCfg = PushConfig.load()
        let pushSub = NSMenu()
        let pe = NSMenuItem(title: "启用手机推送", action: #selector(togglePushEnabled), keyEquivalent: "")
        pe.target = self
        pe.state = pushCfg.enabled ? .on : .off
        pushSub.addItem(pe)
        let pt = NSMenuItem(title: "测试推送", action: #selector(testPush), keyEquivalent: "")
        pt.target = self
        pushSub.addItem(pt)
        pushSub.addItem(.separator())
        for (title, key) in [("需要你", "blocked"), ("完成", "success"), ("出错", "error")] {
            let it = NSMenuItem(title: title, action: #selector(togglePushState(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            it.state = (pushCfg.states[key] ?? false) ? .on : .off
            pushSub.addItem(it)
        }
        pushSub.addItem(.separator())
        let ps = NSMenuItem(title: "设置 Bark…", action: #selector(pushSettings), keyEquivalent: "")
        ps.target = self
        pushSub.addItem(ps)
        let pushItem = NSMenuItem(title: "手机推送", action: nil, keyEquivalent: "")
        pushItem.submenu = pushSub
        menu.addItem(pushItem)

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
        let host = (info?["host"] as? String)
        let ref = (info?["ref"] as? String)
        jump(agent: agent, directory: (dir?.isEmpty == false) ? dir : nil, sessionId: sid,
             host: (host?.isEmpty == false) ? host : nil,
             ref: (ref?.isEmpty == false) ? ref : nil)
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

    @objc private func toggleAckOnFocus() {
        let d = UserDefaults.standard
        d.set(!(d.object(forKey: "ui.ackOnFocus") as? Bool ?? true), forKey: "ui.ackOnFocus")
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

    @objc private func toggleFloatingHoverFade() {
        floating.setHoverFade(!floating.settings.hoverFade)
    }

    @objc private func setFloatingHoverOpacity(_ sender: NSMenuItem) {
        floating.setHoverOpacity(Double(sender.tag) / 100.0)
    }

    // MARK: - Phone / watch push (Bark)

    @objc private func togglePushEnabled() {
        var cfg = PushConfig.load()
        cfg.enabled.toggle()
        cfg.save()
        push.reload()
        if cfg.enabled && cfg.url.isEmpty { pushSettings() }
    }

    @objc private func togglePushState(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var cfg = PushConfig.load()
        cfg.states[key] = !(cfg.states[key] ?? false)
        cfg.save()
        push.reload()
    }

    @objc private func testPush() {
        push.reload()
        guard !PushConfig.load().url.isEmpty else { pushSettings(); return }
        push.sendTest()
    }

    @objc private func pushSettings() {
        let cfg = PushConfig.load()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Bark 推送设置"
        alert.informativeText = "在 iPhone 的 Bark App 里复制 key,粘贴到下面。\n" +
            "可填完整地址 https://api.day.app/<KEY>,也可只填 <KEY>。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = cfg.url
        field.placeholderString = "https://api.day.app/<KEY>"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var next = cfg
        next.url = PushConfig.normalizedURL(field.stringValue)
        guard !next.url.isEmpty else { return }
        next.enabled = true
        next.save()
        push.reload()
        appLog("push settings saved host=\(URL(string: next.url)?.host ?? "-")")
        push.sendTest()
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
