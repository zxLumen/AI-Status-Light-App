import Foundation
import AppKit

/// Reads the opencode session → project directory mapping straight from
/// opencode's SQLite database (read-only), so precise window jumping works
/// without waiting for the plugin to re-report directories.
enum OpenCodeDB {
    static var path: String {
        let env = ProcessInfo.processInfo.environment
        if let p = env["OPENCODE_DB"], !p.isEmpty {
            return (p as NSString).expandingTildeInPath
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db").path
    }

    static func sessionDirectory(_ sessionId: String) -> String? {
        guard !sessionId.isEmpty,
              sessionId.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil,
              FileManager.default.fileExists(atPath: path) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = ["file:\(path)?mode=ro",
                       "SELECT directory FROM session WHERE id='\(sessionId)';"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}

/// Focuses the exact VS Code window for a folder via VS Code's own CLI
/// (`code <folder>`), which needs no Accessibility permission.
enum VSCodeCLI {
    static func focus(directory: String) -> Bool {
        guard !directory.isEmpty else { return false }
        let ws = NSWorkspace.shared
        guard let appURL = ws.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode")
                ?? ws.urlForApplication(withBundleIdentifier: "com.microsoft.VSCodeInsiders") else { return false }
        let cli = appURL.appendingPathComponent("Contents/Resources/app/bin/code").path
        guard FileManager.default.isExecutableFile(atPath: cli) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = [directory]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
