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
}
