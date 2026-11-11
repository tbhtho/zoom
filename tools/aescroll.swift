import Cocoa

// Posts one synthetic scroll gesture at a point, optionally with Control.
// usage: aescroll <dy> <x> <y> <count> [ctrl]
let a = CommandLine.arguments
guard a.count >= 5, let dy = Int32(a[1]), let x = Double(a[2]), let y = Double(a[3]),
      let count = Int(a[4]) else {
    FileHandle.standardError.write(Data("usage: aescroll dy x y count [ctrl]\n".utf8))
    exit(64)
}
let ctrl = a.contains("ctrl")
let src = CGEventSource(stateID: .hidSystemState)
for _ in 0..<count {
    guard let e = CGEvent(scrollWheelEvent2Source: src, units: .line,
                          wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { exit(1) }
    if ctrl { e.flags = .maskControl }
    e.location = CGPoint(x: x, y: y)
    e.post(tap: .cghidEventTap)
    usleep(30_000)
}
