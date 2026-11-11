import Cocoa
import ApplicationServices
import ServiceManagement

// MARK: - Config

struct Config {
    var enabled = true
    var topFraction: Double? = nil   // override; nil = read AE workspace layout
    var chromeTop: Double = 64       // title bar + tool bar above the panel area
    var statusBar: Double = 17       // status bar below the panel area
    var invert: Bool = false         // Control+scroll up = zoom out
    var mode: String = "optionScroll" // "optionScroll" (native, cursor-centred) or "keys" (= / - shortcuts)
    var verbose = false

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AETimelineZoom/config.json")

    static func load() -> Config {
        var c = Config()
        guard let d = try? Data(contentsOf: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return c }
        if let v = o["enabled"] as? Bool { c.enabled = v }
        if let v = o["timelineTopFraction"] as? Double { c.topFraction = v }
        if let v = o["chromeTop"] as? Double { c.chromeTop = v }
        if let v = o["statusBar"] as? Double { c.statusBar = v }
        if let v = o["invertDirection"] as? Bool { c.invert = v }
        if let v = o["mode"] as? String { c.mode = v }
        if let v = o["verbose"] as? Bool { c.verbose = v }
        return c
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var statusItem: NSStatusItem!
    private var zoneWindow: NSWindow?
    private var zoneTimer: Timer?
    private var config = Config.load()
    private var cachedTopFraction: Double?
    private var layoutStamp: Date?
    private var hitCount = 0
    private var permissionTimer: Timer?

    private let aeBundleIDs: Set<String> = ["com.adobe.AfterEffects.application", "com.adobe.AfterEffects"]
    private let marker: Int64 = 0x41455A4F4F4D // "AEZOOM"

    func applicationDidFinishLaunching(_ note: Notification) {
        ensureConfigFile()
        registerLoginItemOnce()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AE Zoom"
        rebuildMenu()
        startTap()
        watchForPermission()
        refreshTopFraction(force: true)
    }

    private func ensureConfigFile() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Config.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Config.path.path) {
            let defaults = """
            {
              "enabled": true,
              "mode": "optionScroll",
              "timelineTopFraction": null,
              "chromeTop": 64,
              "statusBar": 17,
              "invertDirection": false,
              "verbose": false
            }
            """
            try? defaults.write(to: Config.path, atomically: true, encoding: .utf8)
        }
    }

    private func registerLoginItemOnce() {
        let key = "didRegisterLoginItem"
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)
        if SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }
    }

    // MARK: menu

    private func rebuildMenu() {
        let m = NSMenu()
        let toggle = NSMenuItem(title: "Control+Scroll Zoom in Timeline", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = config.enabled ? .on : .off
        m.addItem(toggle)
        m.addItem(NSMenuItem(title: "Show Timeline Zone", action: #selector(showZone), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Recompute Zone from Workspace", action: #selector(recompute), keyEquivalent: ""))
        m.addItem(.separator())
        let info = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "")
        m.addItem(info)
        let openCfg = NSMenuItem(title: "Open Config Folder", action: #selector(openConfig), keyEquivalent: "")
        m.addItem(openCfg)
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    @objc private func toggleEnabled() {
        config.enabled.toggle()
        rebuildMenu()
    }

    @objc private func recompute() {
        cachedTopFraction = nil
        refreshTopFraction(force: true)
        showZone()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.path.deletingLastPathComponent())
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("AETimelineZoom: login item toggle failed: %@", error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: permissions

    private func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Keep trying until the user flips the Accessibility switch; no relaunch needed.
    private func watchForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            guard let self = self else { return }
            if self.tap != nil { t.invalidate(); return }
            if AXIsProcessTrusted() {
                t.invalidate()
                self.startTap()
            }
        }
    }

    // MARK: event tap

    private func startTap() {
        guard ensureAccessibility() else {
            statusItem.button?.title = "AE Zoom — grant Accessibility"
            NSLog("AETimelineZoom: Accessibility not granted; open System Settings > Privacy & Security > Accessibility")
            return
        }
        let mask = (1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { proxy, type, event, refcon in
                                              guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                                              let app = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                                              return app.handle(proxy: proxy, type: type, event: event)
                                          },
                                          userInfo: refcon) else {
            statusItem.button?.title = "AE Zoom — tap failed"
            NSLog("AETimelineZoom: CGEvent.tapCreate failed (Accessibility?)")
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        statusItem.button?.title = "AE Zoom"
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        guard config.enabled else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }
        // Vertical intent only; leave horizontal pans alone.
        let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        guard config.enabled, abs(dy) > abs(dx) else { return Unmanaged.passUnretained(event) }

        guard let (pid, rect) = timelineRectUnderPointer() else { return Unmanaged.passUnretained(event) }
        let p = event.location
        _ = pid

        let action = ScrollRouter.action(dy: dy,
                                         dx: dx,
                                         control: event.flags.contains(.maskControl),
                                         inTimeline: rect.contains(p),
                                         enabled: config.enabled,
                                         mode: config.mode)
        guard case .zoom(let delta) = action else { return Unmanaged.passUnretained(event) }

        hitCount += 1
        if config.verbose {
            NSLog("AETimelineZoom: Ctrl+scroll %.2f at (%.0f,%.0f) inside timeline %@ -> zoom",
                  delta, p.x, p.y, NSStringFromRect(rect))
        }

        if config.mode == "keys" {
            postZoomKey(zoomIn: (config.invert ? -delta : delta) > 0)
            return nil
        }

        let flags = event.flags
        guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
        var newFlags = flags
        newFlags.remove(.maskControl)   // AE's native gesture is Option+scroll
        newFlags.insert(.maskAlternate)
        if config.invert {
            copy.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: -delta)
            copy.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -delta)
        }
        copy.flags = newFlags
        copy.setIntegerValueField(.eventSourceUserData, value: marker)
        copy.post(tap: .cgSessionEventTap)
        return nil // swallow only the Control+scroll event
    }

    private func postZoomKey(zoomIn: Bool) {
        let vk: CGKeyCode = zoomIn ? 0x18 /* = */ : 0x1B /* - */
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: false) {
            down.setIntegerValueField(.eventSourceUserData, value: marker)
            up.setIntegerValueField(.eventSourceUserData, value: marker)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: geometry

    private var lastStat = Date.distantPast

    /// Short version string of the frontmost After Effects install (e.g. "22.6",
    /// "25.6"), used to pick that version's workspace layout file.
    private func frontmostAEVersion() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier, aeBundleIDs.contains(bid),
              let url = app.bundleURL else { return nil }
        let plist = url.appendingPathComponent("Contents/Info.plist")
        if let d = NSDictionary(contentsOf: plist),
           let v = d["CFBundleShortVersionString"] as? String { return v }
        return nil
    }

    private func refreshTopFraction(force: Bool = false) {
        if !force && Date().timeIntervalSince(lastStat) < 5 { return }
        lastStat = Date()
        let path = AELayout.workspacePath(forVersion: frontmostAEVersion())
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        if cachedTopFraction == nil || stamp != layoutStamp {
            layoutStamp = stamp
            cachedTopFraction = AELayout.timelineTopFraction(path: path)
            if config.verbose { NSLog("AETimelineZoom: timelineTopFraction=%@", String(describing: cachedTopFraction)) }
        }
    }

    private func aeWindowRect() -> (pid_t, CGRect)? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bid = front.bundleIdentifier, aeBundleIDs.contains(bid) else { return nil }
        let pid = front.processIdentifier
        return aeWindowRect(for: pid).map { (pid, $0) }
    }

    private func aeWindowRect(for pid: pid_t) -> CGRect? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let wins = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var best: CGRect?
        for w in wins {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid else { continue }
            guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if r.width < 400 || r.height < 300 { continue }
            if best == nil || r.width * r.height > best!.width * best!.height { best = r }
        }
        return best
    }

    private func timelineRectUnderPointer() -> (pid_t, CGRect)? {
        guard let (pid, win) = aeWindowRect() else { return nil }
        refreshTopFraction()
        let frac = config.topFraction ?? cachedTopFraction ?? 0.68
        let top = win.minY + config.chromeTop + frac * (win.height - config.chromeTop - config.statusBar)
        let rect = CGRect(x: win.minX, y: top, width: win.width,
                          height: win.maxY - config.statusBar - top)
        return (pid, rect)
    }

    // MARK: zone overlay

    @objc private func showZone() {
        guard let (_, win) = aeWindowRect() else { return }
        let frac = config.topFraction ?? cachedTopFraction ?? 0.68
        let top = win.minY + config.chromeTop + frac * (win.height - config.chromeTop - config.statusBar)
        let rect = CGRect(x: win.minX, y: top, width: win.width, height: win.maxY - config.statusBar - top)

        zoneWindow?.orderOut(nil)
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.16)
        w.ignoresMouseEvents = true
        w.level = .floating
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .transient]
        let label = NSTextField(labelWithString: "Ctrl+scroll = timeline zoom")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 12, y: rect.height - 26)
        let content = NSView(frame: CGRect(origin: .zero, size: rect.size))
        content.wantsLayer = true
        content.layer?.borderColor = NSColor.systemBlue.cgColor
        content.layer?.borderWidth = 2
        content.addSubview(label)
        w.contentView = content
        w.orderFrontRegardless()
        zoneWindow = w

        zoneTimer?.invalidate()
        zoneTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.zoneWindow?.orderOut(nil)
            self?.zoneWindow = nil
        }
    }
}

let app = NSApplication.shared

if CommandLine.arguments.contains("--axdump") {
    exit(AXDump.run())
}

if CommandLine.arguments.contains("--router-selftest") {
    // Pure routing checks; no AE, no Accessibility, no event tap.
    let cases: [(name: String, dy: Double, dx: Double, ctrl: Bool, inside: Bool,
                 enabled: Bool, mode: String, expect: ScrollRouter.Action)] = [
        ("plain scroll in timeline passes", 3, 0, false, true, true, "optionScroll", .passThrough),
        ("ctrl+scroll down in timeline zooms", -3, 0, true, true, true, "optionScroll", .zoom(delta: -3)),
        ("ctrl+scroll up in timeline zooms", 3, 0, true, true, true, "optionScroll", .zoom(delta: 3)),
        ("ctrl+scroll outside timeline passes", 3, 0, true, false, true, "optionScroll", .passThrough),
        ("plain scroll outside passes", 3, 0, false, false, true, "optionScroll", .passThrough),
        ("ctrl+horizontal passes", 0, 3, true, true, true, "optionScroll", .passThrough),
        ("disabled passes everything", 3, 0, true, true, false, "optionScroll", .passThrough),
        ("keys mode still zooms", 3, 0, true, true, true, "keys", .zoom(delta: 3))
    ]
    var ok = true
    for c in cases {
        let got = ScrollRouter.action(dy: c.dy, dx: c.dx, control: c.ctrl,
                                      inTimeline: c.inside, enabled: c.enabled, mode: c.mode)
        let pass = got == c.expect
        if !pass { ok = false }
        print("\(pass ? "PASS" : "FAIL") \(c.name) -> \(got)")
    }
    exit(ok ? 0 : 2)
}

if CommandLine.arguments.contains("--selftest") {
    let ae = ["com.adobe.AfterEffects.application", "com.adobe.AfterEffects"]
        .compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        .first
    guard let ae = ae else {
        print("selftest: After Effects is not running")
        exit(1)
    }
    let pid = ae.processIdentifier
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let wins = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
    var win = CGRect.zero
    for w in wins where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if r.width * r.height > win.width * win.height { win = r }
    }
    guard win.width > 0 else { print("selftest: no window"); exit(1) }
    let frac = Config.load().topFraction ?? AELayout.timelineTopFraction() ?? 0.68
    let chromeTop = Config.load().chromeTop, statusBar = Config.load().statusBar
    let top = win.minY + chromeTop + frac * (win.height - chromeTop - statusBar)
    let rect = CGRect(x: win.minX, y: top, width: win.width, height: win.maxY - statusBar - top)
    print("window: \(win)")
    print("timeline fraction: \(String(format: "%.4f", frac))")
    print("timeline rect: \(rect)")
    let probes: [(String, CGPoint, Bool)] = [
        ("centre of timeline", CGPoint(x: rect.midX, y: rect.midY), true),
        ("just inside top", CGPoint(x: rect.midX, y: rect.minY + 4), true),
        ("just above top", CGPoint(x: rect.midX, y: rect.minY - 4), false),
        ("composition viewer", CGPoint(x: win.midX, y: win.minY + 300), false)
    ]
    var ok = true
    for (label, p, expected) in probes {
        let inside = rect.contains(p)
        if inside != expected { ok = false }
        print("\(inside == expected ? "PASS" : "FAIL") \(label) \(p) inside=\(inside) expected=\(expected)")
    }
    exit(ok ? 0 : 2)
}

if CommandLine.arguments.contains("--status") {
    print("accessibility_trusted: \(AXIsProcessTrusted())")
    print("timeline_top_fraction: \(AELayout.timelineTopFraction().map { String(format: "%.4f", $0) } ?? "nil")")
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    let data = FileManager.default.contents(atPath: AELayout.defaultWorkspacePath())
    print("bytes read: \(data?.count ?? -1)")
    let frac = AELayout.timelineTopFraction()
    print("workspace: \(AELayout.defaultWorkspacePath())")
    print("timelineTopFraction: \(frac.map { String(format: "%.4f", $0) } ?? "nil")")
    exit(frac == nil ? 1 : 0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
