import Foundation

/// Decides what happens to one scroll-wheel event before any Cocoa/CoreGraphics
/// calls are made, so the routing rule can be exercised without AE running.
///
/// Rule: Control + vertical scroll inside the Timeline panel zooms. Everything
/// else is left untouched and reaches After Effects as a normal scroll.
enum ScrollRouter {
    enum Action: Equatable {
        case passThrough
        case zoom(delta: Double)
    }

    static func action(dy: Double,
                       dx: Double,
                       control: Bool,
                       inTimeline: Bool,
                       enabled: Bool,
                       mode: String) -> Action {
        guard enabled else { return .passThrough }
        guard inTimeline else { return .passThrough }
        // Vertical intent only; leave horizontal panning alone even with Control.
        guard abs(dy) > abs(dx) else { return .passThrough }
        guard control else { return .passThrough }
        guard mode != "off" else { return .passThrough }
        return .zoom(delta: dy)
    }
}
