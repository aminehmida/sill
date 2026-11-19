import ApplicationServices
import Foundation
import StreamProtocol

/// Whether an app's focused element takes text (kind 64, TextFocus.swift): every Accessibility call
/// for it on its own thread `sill.textfocus`, never the main actor, each element with a short
/// timeout so an app that does not answer costs at most that. Reads the role, the subrole, whether
/// the value can be set and whether a selected range exists; never the value itself.
///
/// The app last read is also observed (AXObserver: focused element or window changed), so a field
/// the Mac focuses by itself (an app opening on its search box, a sheet, a ⌘L from the Mac) is told
/// at once. An observer needs a run loop, hence the thread rather than a queue. Apps that post no
/// focus notification (some Electron and web views) are covered by the coordinator's checks.
final class TextFocusReader: @unchecked Sendable {
    private static let timeout: Float = 0.2
    /// The thread's run loop: the observer's source, and every block `perform` hands it.
    private let runLoop: CFRunLoop
    /// A focus the observer read: the app's pid and what it says. On the thread.
    private let onChange: @Sendable (pid_t, TextFocus) -> Void
    // On the thread from here on.
    /// Apps already asked to build their Accessibility tree (Electron's AXManualAccessibility).
    private var askedForTree = Set<pid_t>()
    private var observer: AXObserver?
    private var observedPID: pid_t = 0

    init(onChange: @escaping @Sendable (pid_t, TextFocus) -> Void) {
        self.onChange = onChange
        runLoop = Self.startThread()
    }

    /// Reads `pid`'s focused element on the thread, then calls `done` there; observes `pid` from now
    /// on (no other app).
    func read(pid: pid_t, done: @escaping @Sendable (TextFocus) -> Void) {
        perform { [self] in
            observe(pid)
            done(focusedElement(pid: pid))
        }
    }

    /// No app observed: nothing streams, the app is not frontmost, or no device asks.
    func stop() {
        perform { [self] in stopObserving() }
    }

    private func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private static func startThread() -> CFRunLoop {
        final class Box: @unchecked Sendable { var loop: CFRunLoop? }
        let box = Box(), ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.loop = CFRunLoopGetCurrent()
            // A source that never fires keeps the run loop running with no observer added.
            var context = CFRunLoopSourceContext()
            CFRunLoopAddSource(box.loop, CFRunLoopSourceCreate(nil, 0, &context), .defaultMode)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "sill.textfocus"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        return box.loop!
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        if askedForTree.insert(pid).inserted {
            // Electron apps (VS Code, Slack, Discord) build their tree only when asked; any other app
            // refuses the attribute, which changes nothing.
            _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        return app
    }

    // MARK: The observer

    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let reader = Unmanaged<TextFocusReader>.fromOpaque(refcon).takeUnretainedValue()
        let pid = reader.observedPID
        guard pid != 0 else { return }
        reader.onChange(pid, reader.focusedElement(pid: pid))
    }

    /// An app that refuses every notification (not yet launched far enough, or no Accessibility) is
    /// tried again at the next read.
    private func observe(_ pid: pid_t) {
        guard pid != observedPID else { return }
        stopObserving()
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
        let app = application(pid), refcon = Unmanaged.passUnretained(self).toOpaque()
        var added = false
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            if AXObserverAddNotification(created, app, name as CFString, refcon) == .success { added = true }
        }
        guard added else { return }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
    }

    private func stopObserving() {
        if let observer { CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        observedPID = 0
    }

    // MARK: The read

    private func focusedElement(pid: pid_t) -> TextFocus {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application(pid), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
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
