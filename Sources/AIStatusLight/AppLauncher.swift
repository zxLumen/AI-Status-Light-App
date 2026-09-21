import AppKit

/// Maps an agent to the app that hosts its task, and brings the right window
/// forward. opencode usually runs in the VS Code integrated terminal, so VS Code
/// is preferred. Resolution order for the window: VS Code CLI (by project
/// directory) → Accessibility title match → activate the whole app.
enum AppLauncher {
    static func targetBundleIds(for agent: String) -> [String] {
        switch agent.lowercased() {
        case "opencode": return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "ai.opencode.desktop"]
        case "cursor":   return ["com.todesktop.230313mzl4w4u92"]
        default:         return []
        }
    }

    static func canJump(agent: String) -> Bool {
        !targetBundleIds(for: agent).isEmpty
    }

    /// Resolve the project directory for a session: prefer what the store has,
    /// else look it up in opencode's database.
    static func directory(for agent: String, directory: String?, sessionId: String?) -> String? {
        if let d = directory, !d.isEmpty { return d }
        if agent.lowercased() == "opencode", let sid = sessionId, !sid.isEmpty {
            return OpenCodeDB.sessionDirectory(sid)
        }
        return nil
    }

    @discardableResult
    static func activate(agent: String, directory: String? = nil, sessionId: String? = nil) -> Bool {
        let ids = targetBundleIds(for: agent)
        guard let primary = ids.first else { return false }
        let dir = self.directory(for: agent, directory: directory, sessionId: sessionId)

        // 1) VS Code CLI — precise per-folder window focus, no permission needed.
        if primary.hasPrefix("com.microsoft.VSCode"), let d = dir, VSCodeCLI.focus(directory: d) {
            return true
        }

        // 2) Accessibility title match (needs permission).
        if let d = dir {
            let folder = (d as NSString).lastPathComponent
            for bid in ids where !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty {
                if WindowFocuser.focus(bundleId: bid, matching: folder) { return true }
            }
        }

        // 3) OpenCode desktop deep link.
        if primary == "ai.opencode.desktop", let d = dir,
           let encoded = d.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "opencode://open-project?directory=\(encoded)") {
            NSWorkspace.shared.open(url)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: primary).first {
                app.activate(options: [.activateAllWindows])
            }
            return true
        }

        // 4) Last resort: activate the whole app (launch if needed).
        for bid in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: primary) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        return false
    }
}
