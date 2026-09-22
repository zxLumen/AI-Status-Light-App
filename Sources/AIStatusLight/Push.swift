import Foundation

/// Push configuration, stored outside the repo in
/// `~/.ai-status-light/push.json` (the endpoint contains a secret key).
struct PushConfig: Codable {
    var enabled: Bool = false
    var provider: String = "bark"
    var url: String = ""                       // e.g. https://api.day.app/<KEY>
    var states: [String: Bool] = ["blocked": true, "error": true, "success": true]
    var level: String = "timeSensitive"        // "needs you"
    var successLevel: String = "active"        // error / success
    var sound: String = "default"
    var cooldown: Double = 60                  // per session+state dedupe window
    /// Notification icon (iOS 15+); set to "" to keep Bark's own icon.
    var icon: String? = PushConfig.defaultIconURL
    /// Bark `id` mode: "random" (each push is new), "stable" (same session+state
    /// updates the same notification, so re-deliveries collapse), "off".
    var idMode: String = "random"

    /// Public copy of `docs/images/icon-256.png` (jsDelivr is reachable from
    /// the iPhone; raw.githubusercontent.com often is not in mainland China).
    static let defaultIconURL =
        "https://cdn.jsdelivr.net/gh/zxLumen/AI-Status-Light-App@main/docs/images/icon-256.png"

    static var path: URL { StateStore.home.appendingPathComponent("push.json") }

    init() {}

    // Tolerant decoding: missing keys fall back to the defaults above, so new
    // fields can be added without breaking an existing push.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PushConfig()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? d.provider
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? d.url
        states = try c.decodeIfPresent([String: Bool].self, forKey: .states) ?? d.states
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? d.level
        successLevel = try c.decodeIfPresent(String.self, forKey: .successLevel) ?? d.successLevel
        sound = try c.decodeIfPresent(String.self, forKey: .sound) ?? d.sound
        cooldown = try c.decodeIfPresent(Double.self, forKey: .cooldown) ?? d.cooldown
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? d.icon
        idMode = try c.decodeIfPresent(String.self, forKey: .idMode) ?? d.idMode
    }

    static func load() -> PushConfig {
        guard let data = try? Data(contentsOf: path),
              let cfg = try? JSONDecoder().decode(PushConfig.self, from: data) else {
            return PushConfig()
        }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? FileManager.default.createDirectory(at: StateStore.home, withIntermediateDirectories: true)
        try? data.write(to: PushConfig.path)
    }

    /// Accept a bare Bark key as well as a full URL.
    static func normalizedURL(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if s.lowercased().hasPrefix("http") { return s }
        return "https://api.day.app/" + s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Sends a phone/watch push (Bark) when a session transitions into a key state.
/// HTTP happens on a background queue; the secret key is never logged.
final class PushNotifier {
    var log: ((String) -> Void)?
    private var config = PushConfig.load()
    private var lastSent: [String: Double] = [:]     // "sid|state" -> unix ts
    private let queue = DispatchQueue(label: "aistatus.push")

    func reload() { config = PushConfig.load() }
    var isEnabled: Bool { config.enabled && !config.url.isEmpty }
    func stateEnabled(_ state: String) -> Bool { config.enabled && (config.states[state] ?? false) }

    static func title(for state: String) -> String {
        switch state {
        case "blocked": return "需要你"
        case "error":   return "出错"
        case "success": return "完成"
        default:        return state
        }
    }

    /// Bark-style JSON payload (pure; unit-testable).
    static func payload(title: String, body: String, level: String,
                        group: String?, badge: Int?, sound: String?,
                        icon: String? = nil) -> [String: Any] {
        var p: [String: Any] = ["title": title, "body": body, "level": level]
        if let group, !group.isEmpty { p["group"] = group }
        if let badge { p["badge"] = badge }
        if let sound, !sound.isEmpty { p["sound"] = sound }
        if let icon, !icon.isEmpty { p["icon"] = icon }
        return p
    }

    /// Bark notification id for a session state (pure; unit-testable).
    static func barkID(mode: String, sessionId: String, state: String) -> String? {
        switch mode {
        case "off":    return nil
        case "stable": return "\(sessionId)|\(state)"
        default:       return String(Int.random(in: 1...9_999_999))
        }
    }

    /// Notify for every transition that is enabled and not within its cooldown.
    @discardableResult
    func maybeNotify(_ transitions: [SessionRecord], badge: Int) -> [SessionRecord] {
        guard isEnabled else { return [] }
        let now = Date().timeIntervalSince1970
        var sent: [SessionRecord] = []
        for rec in transitions {
            guard config.states[rec.state] ?? false else { continue }
            let key = "\(rec.sessionId)|\(rec.state)"
            if let t = lastSent[key], now - t < config.cooldown { continue }
            lastSent[key] = now
            post(Self.payload(title: Self.title(for: rec.state),
                              body: Self.body(for: rec),
                              level: rec.state == "blocked" ? config.level : config.successLevel,
                              group: rec.sessionId, badge: badge, sound: config.sound,
                              icon: config.icon),
                 tag: "\(rec.state) sid=\(rec.sessionId)",
                 id: Self.barkID(mode: config.idMode, sessionId: rec.sessionId, state: rec.state))
            sent.append(rec)
        }
        return sent
    }

    func sendTest() {
        guard !config.url.isEmpty else { log?("push test skipped: url empty"); return }
        post(Self.payload(title: "测试推送",
                          body: "AI 状态灯 · 在手机/手表上看到这条即配置成功",
                          level: config.level, group: "test", badge: nil, sound: config.sound,
                          icon: config.icon),
             tag: "test", id: "aistatus-test")
    }

    static func body(for rec: SessionRecord) -> String {
        var lines: [String] = []
        let name = (rec.name?.isEmpty == false) ? rec.name! : rec.agent
        lines.append("\(name) · \(rec.agent)")
        if let m = rec.message, !m.isEmpty { lines.append(m) }
        if let d = rec.dir, !d.isEmpty { lines.append((d as NSString).lastPathComponent) }
        return lines.joined(separator: "\n")
    }

    private func post(_ payload: [String: Any], tag: String, id: String?) {
        guard let base = URL(string: config.url),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            log?("push \(tag) invalid url")
            return
        }
        // Bark `id`: pushes sharing an id update the same notification.
        var url = base
        if let id, !id.isEmpty,
           var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            var items = comps.queryItems ?? []
            items.append(URLQueryItem(name: "id", value: id))
            comps.queryItems = items
            if let u = comps.url { url = u }
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 10
        let host = url.host ?? "?"                 // never log the key in the path
        let title = (payload["title"] as? String) ?? "-"
        queue.async { [weak self] in
            URLSession.shared.dataTask(with: req) { _, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let ok = err == nil && (200..<300).contains(code)
                let suffix = err.map { " err=\($0.localizedDescription)" } ?? ""
                self?.log?("push \(tag) title=\(title) id=\(id ?? "-") host=\(host) ok=\(ok) code=\(code)\(suffix)")
            }.resume()
        }
    }
}
