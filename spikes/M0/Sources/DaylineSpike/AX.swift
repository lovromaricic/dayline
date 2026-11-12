import ApplicationServices

/// Thin helpers over the C Accessibility API.
enum AX {
    static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        value(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        (value(el, name) as? NSNumber)?.boolValue
    }

    static func url(_ el: AXUIElement, _ name: String) -> URL? {
        value(el, name) as? URL
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        (value(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func role(_ el: AXUIElement) -> String? { string(el, kAXRoleAttribute) }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    /// Prints the native part of the tree (does not descend into web content).
    static func dump(_ el: AXUIElement, depth: Int = 0, maxDepth: Int = 14) {
        guard depth <= maxDepth else { return }
        let role = role(el) ?? "?"
        var parts = [role]
        for name in [kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, "AXDOMIdentifier", kAXHelpAttribute] {
            if let s = string(el, name), !s.isEmpty { parts.append("\(name.dropFirst(2))=\"\(s.prefix(80))\"") }
        }
        if let s = string(el, kAXValueAttribute), !s.isEmpty { parts.append("Value=\"\(s.prefix(80))\"") }
        if let u = url(el, "AXURL") { parts.append("URL=\(u.absoluteString.prefix(80))") }
        Log.raw(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        if role == "AXWebArea" || role == kAXTabGroupRole { return }
        for child in children(el) { dump(child, depth: depth + 1, maxDepth: maxDepth) }
    }
}
