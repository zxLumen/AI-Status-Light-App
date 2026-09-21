import AppKit
import ApplicationServices

/// Focuses a specific window of another app via the Accessibility API.
/// Used to jump to the right VS Code window when several are open.
enum WindowFocuser {
    /// Prompt (once) for Accessibility permission; returns current trust state.
    @discardableResult
    static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let key = "ax.prompted"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Title of the app's currently focused window (nil if untrusted / unknown).
    static func focusedWindowTitle(bundleId: String) -> String? {
        guard isTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }

    /// Activate the app and raise the window whose title contains `needle`.
    /// Returns false when unmapped/untrusted/not found (caller falls back).
    @discardableResult
    static func focus(bundleId: String, matching needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { return false }
        app.activate(options: [.activateAllWindows])
        guard isTrusted else { return false }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return false }

        let target = needle.lowercased()
        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else { continue }
            if title.lowercased().contains(target) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                return true
            }
        }
        return false
    }
}
