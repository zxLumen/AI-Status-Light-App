import Foundation

struct DisplayInfo: Decodable {
    let color: String
    let label: String
}

/// The single-source state contract (aistatus/states.json), loaded at runtime so
/// the menu bar app and the host bridge always agree on priority / TTL / colours.
struct Contract: Decodable {
    let modes: [String]
    let eventToMode: [String: String]
    let priority: [String: Int]
    let defaultTtl: [String: Double]
    let display: [String: DisplayInfo]
    let agents: [String]

    enum CodingKeys: String, CodingKey {
        case modes, priority, display, agents
        case eventToMode = "event_to_mode"
        case defaultTtl = "default_ttl"
    }

    init(
        modes: [String],
        eventToMode: [String: String],
        priority: [String: Int],
        defaultTtl: [String: Double],
        display: [String: DisplayInfo],
        agents: [String]
    ) {
        self.modes = modes
        self.eventToMode = eventToMode
        self.priority = priority
        self.defaultTtl = defaultTtl
        self.display = display
        self.agents = agents
    }

    func label(_ mode: String) -> String { display[mode]?.label ?? mode }
    func colorHex(_ mode: String) -> String { display[mode]?.color ?? "#8a8f98" }
    func ttl(_ state: String) -> Double { defaultTtl[state] ?? 60 }
    func priorityOf(_ state: String) -> Int { priority[state] ?? -1 }
    func mode(for state: String) -> String { eventToMode[state] ?? "idle" }

    static func load() -> Contract {
        let env = ProcessInfo.processInfo.environment
        let cwd = FileManager.default.currentDirectoryPath
        var candidates: [URL] = []
        if let p = env["AISTATUS_CONTRACT"], !p.isEmpty {
            candidates.append(URL(fileURLWithPath: (p as NSString).expandingTildeInPath))
        }
        candidates.append(StateStore.home.appendingPathComponent("states.json"))
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("states.json"))
        }
        candidates.append(URL(fileURLWithPath: cwd).appendingPathComponent("aistatus/states.json"))
        candidates.append(URL(fileURLWithPath: cwd).appendingPathComponent("Resources/states.json"))

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let c = try? JSONDecoder().decode(Contract.self, from: data) {
                return c
            }
        }
        return .fallback
    }

    static let fallback = Contract(
        modes: ["off", "idle", "thinking", "working", "busy", "success", "error",
                "blocked", "alarm", "demo", "traffic", "red", "yellow", "green"],
        eventToMode: ["idle": "idle", "thinking": "thinking", "working": "working",
                      "busy": "busy", "success": "success", "error": "error", "blocked": "blocked"],
        priority: ["blocked": 60, "error": 50, "success": 40, "busy": 30,
                   "working": 20, "thinking": 15, "idle": 0],
        defaultTtl: ["blocked": 300, "error": 60, "success": 25, "busy": 90,
                     "working": 90, "thinking": 90, "idle": 15],
        display: [
            "off": .init(color: "#8a8f98", label: "off"),
            "idle": .init(color: "#8a8f98", label: "idle"),
            "thinking": .init(color: "#f4c20d", label: "thinking"),
            "working": .init(color: "#f4c20d", label: "working"),
            "busy": .init(color: "#ff8a00", label: "busy"),
            "success": .init(color: "#1faa59", label: "success"),
            "error": .init(color: "#e8453c", label: "error"),
            "blocked": .init(color: "#b06fe8", label: "needs you"),
        ],
        agents: ["claude", "cursor", "codex", "opencode", "manual"]
    )
}
