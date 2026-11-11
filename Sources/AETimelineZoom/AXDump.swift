import Cocoa
import ApplicationServices

/// Read-only accessibility dump, used to confirm whether After Effects exposes
/// its panels (and the Timeline rect) through AX once the app has been granted
/// Accessibility. Run: AETimelineZoom --axdump
enum AXDump {
    static func run() -> Int32 {
        guard AXIsProcessTrusted() else {
            print("AXIsProcessTrusted: false - grant Accessibility first")
            return 1
        }
        guard let ae = NSRunningApplication.runningApplications(withBundleIdentifier: "com.adobe.AfterEffects.application").first else {
            print("After Effects is not running")
            return 1
        }
        let pid = ae.processIdentifier
        print("pid: \(pid)")
        let appEl = AXUIElementCreateApplication(pid)

        func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
        }
        func frame(_ el: AXUIElement) -> CGRect? {
            guard let rawP = attr(el, kAXPositionAttribute),
                  let rawS = attr(el, kAXSizeAttribute),
                  CFGetTypeID(rawP) == AXValueGetTypeID(),
                  CFGetTypeID(rawS) == AXValueGetTypeID() else { return nil }
            let pv = unsafeDowncast(rawP, to: AXValue.self)
            let sv = unsafeDowncast(rawS, to: AXValue.self)
            var p = CGPoint.zero
            var s = CGSize.zero
            AXValueGetValue(pv, .cgPoint, &p)
            AXValueGetValue(sv, .cgSize, &s)
            return CGRect(origin: p, size: s)
        }
        func dump(_ el: AXUIElement, _ depth: Int) {
            guard depth < 5 else { return }
            let role = attr(el, kAXRoleAttribute) as? String ?? "?"
            let title = attr(el, kAXTitleAttribute) as? String ?? ""
            let desc = attr(el, kAXDescriptionAttribute) as? String ?? ""
            let f = frame(el).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
            print(String(repeating: "  ", count: depth) + "\(role) [\(title)] [\(desc)] \(f)")
            if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for k in kids.prefix(40) { dump(k, depth + 1) }
            }
        }
        dump(appEl, 0)

        if let wins = attr(appEl, kAXWindowsAttribute) as? [AXUIElement], let w = wins.first, let f = frame(w) {
            print("--- hit tests ---")
            for (label, p) in [("comp", CGPoint(x: f.midX, y: f.minY + f.height * 0.35)),
                               ("timeline", CGPoint(x: f.midX, y: f.minY + f.height * 0.85))] {
                var el: AXUIElement?
                let err = AXUIElementCopyElementAtPosition(appEl, Float(p.x), Float(p.y), &el)
                if err == .success, let e = el {
                    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
                    let desc = attr(e, kAXDescriptionAttribute) as? String ?? ""
                    let fr = frame(e).map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
                    print("\(label): \(role) [\(desc)] \(fr)")
                } else {
                    print("\(label): hit test failed (\(err.rawValue))")
                }
            }
        }
        return 0
    }
}
