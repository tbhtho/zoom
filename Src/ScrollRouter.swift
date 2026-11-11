import CoreGraphics
import Foundation

/// Decides what happens to one scroll-wheel event before any Cocoa/CoreGraphics
/// calls are made, so the routing rule can be exercised without AE running.
///
/// Rule: the configured modifier + vertical scroll inside the Timeline panel
/// zooms. Everything else is left untouched and reaches After Effects as a
/// normal scroll. Default modifier is Command.
enum ScrollRouter {
    enum Action: Equatable {
        case passThrough
        case zoom(delta: Double)
    }

    static let modifiers = ["command", "control", "option", "shift"]

    static func normalized(_ name: String) -> String {
        let n = name.lowercased()
        return modifiers.contains(n) ? n : "command"
    }

    static func mask(for modifier: String) -> CGEventFlags? {
        switch normalized(modifier) {
        case "command": return .maskCommand
        case "control": return .maskControl
        case "option": return .maskAlternate
        case "shift": return .maskShift
        default: return nil
        }
    }

    static func displayName(_ modifier: String) -> String {
        switch normalized(modifier) {
        case "command": return "Command"
        case "control": return "Control"
        case "option": return "Option"
        case "shift": return "Shift"
        default: return "Command"
        }
    }

    static func glyph(_ modifier: String) -> String {
        switch normalized(modifier) {
        case "command": return "\u{2318}"
        case "control": return "\u{2303}"
        case "option": return "\u{2325}"
        case "shift": return "\u{21E7}"
        default: return "\u{2318}"
        }
    }

    static func action(dy: Double,
                       dx: Double,
                       flags: CGEventFlags,
                       modifier: String,
                       inTimeline: Bool,
                       enabled: Bool,
                       mode: String) -> Action {
        guard enabled, inTimeline, mode != "off" else { return .passThrough }
        // Vertical intent only; leave horizontal panning alone.
        guard abs(dy) > abs(dx) else { return .passThrough }
        guard let m = mask(for: modifier), flags.contains(m) else { return .passThrough }
        return .zoom(delta: dy)
    }
}
