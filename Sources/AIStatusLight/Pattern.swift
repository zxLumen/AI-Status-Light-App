import Foundation

/// Maps an aistatus mode to per-lamp brightness (red/yellow/green, 0...1) over
/// time. Mirrors the firmware / virtual-light patterns.
enum Pattern {
    static func levels(_ mode: String, _ t: Double) -> (r: Double, y: Double, g: Double) {
        func breathe(_ period: Double) -> Double {
            let p = t.truncatingRemainder(dividingBy: period)
            let half = period / 2
            return p < half ? p / half : (period - p) / half
        }
        func blink(_ period: Double, _ duty: Double) -> Double {
            t.truncatingRemainder(dividingBy: period) < period * duty ? 1 : 0.05
        }
        switch mode {
        case "off":      return (0, 0, 0)
        case "idle":     return (0, 0, 0.12 + breathe(4.0) * 0.22)
        case "thinking": return (0, breathe(2.2), 0)
        case "working":  return (0, breathe(1.2), 0)
        case "busy":     return (0, blink(0.8, 0.35), 0)
        case "success":  return (0, 0, 1)
        case "error":    return (blink(0.35, 0.5), 0, 0)
        case "blocked":
            return t.truncatingRemainder(dividingBy: 1.0) < 0.5 ? (1, 0, 0) : (0, 1, 0)
        case "alarm":
            return t.truncatingRemainder(dividingBy: 0.4) < 0.2 ? (1, 0, 0) : (0, 1, 0)
        case "red":      return (1, 0, 0)
        case "yellow":   return (0, 1, 0)
        case "green":    return (0, 0, 1)
        case "traffic":
            let step = Int(t / 2.0) % 3
            return step == 0 ? (0, 0, 1) : step == 1 ? (0, 1, 0) : (1, 0, 0)
        case "demo":
            let seq = ["thinking", "working", "busy", "success", "blocked", "error"]
            return levels(seq[Int(t / 1.5) % seq.count], t)
        default:         return (0, 0, 0)
        }
    }

    static func isAnimated(_ mode: String) -> Bool {
        switch mode {
        case "off", "success", "red", "yellow", "green": return false
        default: return true
        }
    }
}
