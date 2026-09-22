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

    static var path: URL { StateStore.home.appendingPathComponent("push.json") }

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
                        group: String?, badge: Int?, sound: String?) -> [String: Any] {
        var p: [String: Any] = ["title": title, "body": body, "level": level]
        if let group, !group.isEmpty { p["group"] = group }
        if let badge { p["badge"] = badge }
        if let sound, !sound.isEmpty { p["sound"] = sound }
        return p
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
                              group: rec.sessionId, badge: badge, sound: config.sound),
                 tag: "\(rec.state) sid=\(rec.sessionId)")
            sent.append(rec)
        }
        return sent
    }

    func sendTest() {
        guard !config.url.isEmpty else { log?("push test skipped: url empty"); return }
        post(Self.payload(title: "测试推送",
                          body: "AI 状态灯 · 在手机/手表上看到这条即配置成功",
                          level: config.level, group: "test", badge: nil, sound: config.sound),
             tag: "test")
    }

    static func body(for rec: SessionRecord) -> String {
        var lines: [String] = []
        let name = (rec.name?.isEmpty == false) ? rec.name! : rec.agent
        lines.append("\(name) · \(rec.agent)")
        if let m = rec.message, !m.isEmpty { lines.append(m) }
        if let d = rec.dir, !d.isEmpty { lines.append((d as NSString).lastPathComponent) }
        return lines.joined(separator: "\n")
    }

    private func post(_ payload: [String: Any], tag: String) {
        guard let url = URL(string: config.url),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            log?("push \(tag) invalid url")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 10
        let host = url.host ?? "?"                 // never log the key in the path
        queue.async { [weak self] in
            URLSession.shared.dataTask(with: req) { _, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let ok = err == nil && (200..<300).contains(code)
                let suffix = err.map { " err=\($0.localizedDescription)" } ?? ""
                self?.log?("push \(tag) host=\(host) ok=\(ok) code=\(code)\(suffix)")
            }.resume()
        }
    }
}
