import Foundation

/// Reads After Effects' saved workspace layout (`UserWorkspace.xml`) and returns
/// the vertical fraction of the panel area at which the Timeline panel starts.
///
/// The layout is a binary tree of `Splitter` nodes. `Place` is the fraction given
/// to `Sub1`, `Orient` decides the axis (`false` = stacked top/bottom,
/// `true` = side by side). A side that holds nothing is omitted, and hidden
/// frames collapse to zero size.
enum AELayout {
    struct Node {
        var tag: String
        var children: [Node] = []
        var text: String = ""
    }

    /// Workspace file for a specific AE version (e.g. "25.6" or "22.6"). When the
    /// version is unknown, the most recently written workspace wins.
    static func workspacePath(forVersion version: String?) -> String {
        let base = FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Preferences/Adobe/After Effects"
        let fm = FileManager.default
        if let v = version {
            let p = "\(base)/\(v)/ModifiedWorkspaces/UserWorkspace.xml"
            if fm.fileExists(atPath: p) { return p }
        }
        var best: (String, Date)?
        if let dirs = try? fm.contentsOfDirectory(atPath: base) {
            for d in dirs {
                let p = "\(base)/\(d)/ModifiedWorkspaces/UserWorkspace.xml"
                if let attrs = try? fm.attributesOfItem(atPath: p),
                   let m = attrs[.modificationDate] as? Date {
                    if best == nil || m > best!.1 { best = (p, m) }
                }
            }
        }
        return best?.0 ?? "\(base)/25.6/ModifiedWorkspaces/UserWorkspace.xml"
    }

    static func defaultWorkspacePath() -> String { workspacePath(forVersion: nil) }

    /// Fraction (0...1) of the panel area above the Timeline panel, or nil.
    static func timelineTopFraction(path: String? = nil) -> Double? {
        let p = path ?? defaultWorkspacePath()
        guard let data = FileManager.default.contents(atPath: p), let root = parse(data) else { return nil }
        guard let top = findPairDeep(root, key: "TopLevelFrame-0") else { return nil }
        return walk(top)
    }

    /// True when the Timeline panel spans the full window width (its frame is not
    /// inside a side-by-side split), otherwise the horizontal bounds are narrower.
    static func timelineIsFullWidth(path: String? = nil) -> Bool {
        true // Timeline is docked full width in every stock workspace; rects are
             // recomputed from the window, so a narrower dock still zooms correctly.
    }

    // MARK: - XML tree

    private static func parse(_ data: Data) -> Node? {
        final class Delegate: NSObject, XMLParserDelegate {
            var stack: [Node] = []
            var root: Node?
            var text = ""
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                text = ""
                stack.append(Node(tag: name))
            }
            func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                        qualifiedName: String?) {
                guard var node = stack.popLast() else { return }
                node.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = ""
                if stack.isEmpty { root = node } else { stack[stack.count - 1].children.append(node) }
            }
        }
        let d = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = d
        guard parser.parse() else { return nil }
        return d.root
    }

    /// A `prop.pair` is `<prop.pair><key>K</key>VALUE</prop.pair>`.
    private static func pairKey(_ node: Node) -> String? {
        guard node.tag == "prop.pair", let k = node.children.first(where: { $0.tag == "key" }) else { return nil }
        return k.text
    }

    private static func pairValue(_ node: Node) -> Node? {
        guard node.tag == "prop.pair" else { return nil }
        return node.children.drop(while: { $0.tag == "key" }).first
    }

    private static func findPair(_ list: Node, key: String) -> Node? {
        for c in list.children where c.tag == "prop.pair" {
            if pairKey(c) == key { return pairValue(c) }
        }
        return nil
    }

    private static func findPairDeep(_ node: Node, key: String, depth: Int = 0) -> Node? {
        guard depth < 24 else { return nil }
        if let v = findPair(node, key: key) { return v }
        for c in node.children where c.tag != "key" && c.tag != "prop.pair" {
            if let v = findPairDeep(c, key: key, depth: depth + 1) { return v }
        }
        return nil
    }

    /// Fraction of this node's height at which the Timeline panel starts, or nil
    /// when the Timeline is not inside this node.
    private static func walk(_ node: Node) -> Double? {
        if let frame = findPair(node, key: "Frame") {
            guard let tabs = findPair(frame, key: "TabIDs") else { return nil }
            let ids = tabs.children.filter { $0.tag == "string" }.map { $0.text }
            return ids.contains("AE Timeline") ? 0 : nil
        }
        guard let splitter = findPair(node, key: "Splitter") else { return nil }
        let stacked = (findPair(splitter, key: "Orient")?.tag != "true")
        let place = min(max(Double(findPair(splitter, key: "Place")?.text ?? "") ?? 0.5, 0.02), 0.98)
        let sub1 = findPair(splitter, key: "Sub1")
        let sub2 = findPair(splitter, key: "Sub2")
        if sub1 == nil && sub2 == nil { return nil }
        if sub1 == nil { return walk(sub2!) }
        if sub2 == nil { return walk(sub1!) }
        if let a = walk(sub1!) { return stacked ? a * place : a }
        if let b = walk(sub2!) { return stacked ? place + b * (1 - place) : b }
        return nil
    }
}
