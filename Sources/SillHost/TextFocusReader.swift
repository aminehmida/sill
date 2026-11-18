import ApplicationServices
import Foundation
import StreamProtocol

/// Whether an app's focused element takes text (kind 64, TextFocus.swift): every Accessibility call
/// for it, on its own queue `sill.textfocus`, never the main actor, each element with a short
/// timeout so an app that does not answer costs at most that. Reads the role, the subrole, whether
/// the value can be set and whether a selected range exists; never the value itself.
final class TextFocusReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sill.textfocus", qos: .userInitiated)
    /// Apps already asked to build their Accessibility tree (Electron's AXManualAccessibility); on `queue`.
    private var askedForTree = Set<pid_t>()
    /// A read in flight: a poll that comes meanwhile is skipped. On `queue`.
    private var busy = false
    private static let timeout: Float = 0.2

    /// Reads `pid`'s focused element on the reader's queue, then calls `done` there. A read already in
    /// flight drops this one: the next poll comes soon enough.
    func read(pid: pid_t, done: @escaping @Sendable (TextFocus) -> Void) {
        queue.async { [self] in
            guard !busy else { return }
            busy = true
            let focus = focusedElement(pid: pid)
            busy = false
            done(focus)
        }
    }

    private func focusedElement(pid: pid_t) -> TextFocus {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        if askedForTree.insert(pid).inserted {
            // Electron apps (VS Code, Slack, Discord) build their tree only when asked; any other app
            // refuses the attribute, which changes nothing.
            _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .none }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        func string(_ attribute: String) -> String? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &v) == .success else { return nil }
            return v as? String
        }
        let role = string(kAXRoleAttribute), subrole = string(kAXSubroleAttribute)
        let quick = TextFocus.judge(role: role, subrole: subrole, valueSettable: false, hasSelectedRange: false)
        if quick.editable { return quick }
        var settable: DarwinBoolean = false
        let settableRead = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
        var range: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
        return TextFocus.judge(role: role, subrole: subrole, valueSettable: settableRead && settable.boolValue,
                               hasSelectedRange: hasRange)
    }
}
