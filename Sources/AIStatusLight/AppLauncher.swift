import AppKit

/// Maps an agent to the app that hosts its task, and brings the right window
/// forward. The session's `host` (reported by the plugin: iTerm / VS Code /
/// desktop …) decides the target; without it we fall back to a default list.
enum AppLauncher {
    static func defaultBundleIds(for agent: String) -> [String] {
        switch agent.lowercased() {
        case "opencode": return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "ai.opencode.desktop"]
        case "cursor":   return ["com.todesktop.230313mzl4w4u92"]
        default:         return []
        }
    }

    /// Target bundle ids, preferring the session's reported host.
    static func targetBundleIds(for agent: String, host: String?) -> [String] {
        if let h = host, !h.isEmpty { return [h] }
        return defaultBundleIds(for: agent)
    }

    static func canJump(agent: String) -> Bool {
        !defaultBundleIds(for: agent).isEmpty
    }

    static func directory(for agent: String, directory: String?, sessionId: String?) -> String? {
        if let d = directory, !d.isEmpty { return d }
        if agent.lowercased() == "opencode", let sid = sessionId, !sid.isEmpty {
            return OpenCodeDB.sessionDirectory(sid)
        }
        return nil
    }

    @discardableResult
    static func activate(agent: String, directory: String? = nil, sessionId: String? = nil,
                         host: String? = nil, ref: String? = nil) -> Bool {
        let ids = targetBundleIds(for: agent, host: host)
        guard let primary = ids.first else { return false }
        let dir = self.directory(for: agent, directory: directory, sessionId: sessionId)
        let isVSCode = primary.hasPrefix("com.microsoft.VSCode")

        // iTerm2: select the exact tab by session id.
        if primary == "com.googlecode.iterm2", let r = ref, !r.isEmpty, ITermFocus.focus(sessionRef: r) {
            return true
        }
        // VS Code: focus the window for this project folder via its CLI.
        if isVSCode, let d = dir, VSCodeCLI.focus(directory: d) {
            return true
        }
        // OpenCode desktop: deep link to the project.
        if primary == "ai.opencode.desktop", let d = dir,
           let encoded = d.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "opencode://open-project?directory=\(encoded)") {
            NSWorkspace.shared.open(url)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: primary).first {
                app.activate(options: [.activateAllWindows])
            }
            return true
        }
        // Accessibility title match (precise window, needs permission).
        if let d = dir {
            let folder = (d as NSString).lastPathComponent
            for bid in ids where !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty {
                if WindowFocuser.focus(bundleId: bid, matching: folder) { return true }
            }
        }
        // Last resort: activate the whole app (launch if needed).
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

/// Focuses a specific iTerm2 tab/session via AppleScript (needs Automation
/// permission the first time).
enum ITermFocus {
    static func focus(sessionRef: String) -> Bool {
        let script = """
        tell application "iTerm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if (unique id of s) is "\(sessionRef)" then
                  select t
                  select s
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
