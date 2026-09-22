import Foundation

struct SessionRecord: Decodable {
    let sessionId: String
    let agent: String
    let state: String
    let message: String?
    let ts: Double
    var name: String?
    var dir: String?
    var ack: Bool?
    var host: String?
    var ref: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case agent, state, message, ts, name, dir, ack, host, ref
    }
}

struct Aggregate {
    var mode: String
    var state: String
    var reason: String
    var sessions: [SessionRecord]
    var manual: Bool
}

/// Reads the same on-disk store the agent hooks write into
/// (`~/.ai-status-light`), so the menu bar app is a purely local viewer.
enum StateStore {
    static var home: URL {
        let env = ProcessInfo.processInfo.environment
        if let h = env["AISTATUS_HOME"] ?? env["AI_STATUS_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ai-status-light")
    }

    static var sessionsDir: URL { home.appendingPathComponent("sessions") }
    static var namesPath: URL { home.appendingPathComponent("names.json") }
    static var overridePath: URL { home.appendingPathComponent("override.json") }

    static func names() -> [String: String] {
        guard let data = try? Data(contentsOf: namesPath),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    static var dirsPath: URL { home.appendingPathComponent("dirs.json") }
    static var hostsPath: URL { home.appendingPathComponent("hosts.json") }

    static func dirs() -> [String: String] {
        guard let data = try? Data(contentsOf: dirsPath),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    struct HostInfo: Decodable {
        let host: String?
        let ref: String?
    }

    static func hosts() -> [String: HostInfo] {
        guard let data = try? Data(contentsOf: hostsPath),
              let map = try? JSONDecoder().decode([String: HostInfo].self, from: data) else { return [:] }
        return map
    }

    static func readSessions() -> [SessionRecord] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let names = names()
        let dirs = dirs()
        let hosts = hosts()
        var out: [SessionRecord] = []
        let decoder = JSONDecoder()
        for url in items where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  var rec = try? decoder.decode(SessionRecord.self, from: data) else { continue }
            rec.name = names[rec.sessionId]
            if rec.dir == nil { rec.dir = dirs[rec.sessionId] }
            rec.host = hosts[rec.sessionId]?.host
            rec.ref = hosts[rec.sessionId]?.ref
            out.append(rec)
        }
        return out
    }

    struct Override { let mode: String; let ts: Double; let ttl: Double? }

    static func override() -> Override? {
        guard let data = try? Data(contentsOf: overridePath) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = obj["mode"] as? String, !mode.isEmpty else { return nil }
        let ts = (obj["ts"] as? Double) ?? 0
        let ttl = obj["ttl"] as? Double
        if let ttl, ttl > 0, Date().timeIntervalSince1970 - ts > ttl {
            try? FileManager.default.removeItem(at: overridePath)
            return nil
        }
        return Override(mode: mode, ts: ts, ttl: ttl)
    }

    static func clear() {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension == "json" || url.pathExtension == "tmp" {
                try? fm.removeItem(at: url)
            }
        }
        try? fm.removeItem(at: namesPath)
    }

    static func clearSession(_ sessionId: String) {
        let safe = sessionId.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }
        let url = sessionsDir.appendingPathComponent(String(safe) + ".json")
        try? FileManager.default.removeItem(at: url)
    }

    /// Keep the session listed but mark it "seen": no longer an attention state.
    static func markAcknowledged(_ sessionId: String) {
        let safe = sessionId.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }
        let url = sessionsDir.appendingPathComponent(String(safe) + ".json")
        guard let data = try? Data(contentsOf: url),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let now = Date().timeIntervalSince1970
        obj["ack"] = true
        obj["ts"] = now
        obj["seq"] = Int(now * 1000)
        if let out = try? JSONSerialization.data(withJSONObject: obj) {
            try? out.write(to: url)
        }
    }

    static func setOverride(mode: String, ttl: Double?) {
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var rec: [String: Any] = ["mode": mode, "ts": Date().timeIntervalSince1970]
        if let ttl { rec["ttl"] = ttl }
        if let data = try? JSONSerialization.data(withJSONObject: rec) {
            try? data.write(to: overridePath)
        }
    }
}

enum Aggregator {
    static func aggregate(_ records: [SessionRecord], contract: Contract,
                          now: Double = Date().timeIntervalSince1970) -> Aggregate {
        if let ov = StateStore.override() {
            return Aggregate(mode: ov.mode, state: ov.mode, reason: "manual override",
                             sessions: [], manual: true)
        }
        let live = records.filter { $0.ack != true && now - $0.ts <= contract.ttl($0.state) }
        guard !live.isEmpty else {
            return Aggregate(mode: "idle", state: "idle", reason: "no active sessions",
                             sessions: [], manual: false)
        }
        let best = live.max { contract.priorityOf($0.state) < contract.priorityOf($1.state) }!
        let mode = contract.mode(for: best.state)
        let label = best.name?.isEmpty == false ? best.name! : best.agent
        return Aggregate(mode: mode, state: best.state, reason: "\(label) -> \(best.state)",
                         sessions: live, manual: false)
    }
}
