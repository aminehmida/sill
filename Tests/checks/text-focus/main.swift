// TextFocus (kind 64) on its own: the rule from what Accessibility says of the focused element, the JSON a
// device reads, and the hello's opt-in.
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/text-focus/main.swift -o check && ./check
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

func judge(_ role: String?, _ subrole: String? = nil, settable: Bool = false, range: Bool = false) -> TextFocus {
    TextFocus.judge(role: role, subrole: subrole, valueSettable: settable, hasSelectedRange: range)
}

// MARK: The rule
for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
    check("\(role) takes text", judge(role) == TextFocus(editable: true))
}
check("a search field by its subrole", judge("AXGroup", "AXSearchField") == TextFocus(editable: true))
check("a password field is editable and secure", judge("AXTextField", "AXSecureTextField") == TextFocus(editable: true, secure: true))
check("a password field whatever its role", judge(nil, "AXSecureTextField").secure == true)
check("a settable value with a selection", judge("AXGroup", settable: true, range: true).editable)
check("a settable value without a selection is no field (a slider)", !judge("AXSlider", settable: true).editable)
check("a selection without a settable value is no field (static text)", !judge("AXStaticText", range: true).editable)
for role in ["AXButton", "AXWindow", "AXWebArea", "AXList", "AXScrollArea", "AXStaticText", "AXImage"] {
    check("\(role) takes no text", judge(role) == .none)
}
check("nothing known takes no text", judge(nil) == .none)
check("only a password field is secure", judge("AXTextField").secure == nil)

// MARK: secure only with editable
check("secure dropped when not editable", TextFocus(editable: false, secure: true).secure == nil)
check("secure false is left out", TextFocus(editable: true, secure: false).secure == nil)

// MARK: The wire
check("kind 64", StreamMessageKind.textFocus.rawValue == 64)
check("64 parses as textFocus", StreamMessageKind(rawValue: 64) == .textFocus)
let plain = String(data: try! JSONEncoder().encode(TextFocus(editable: true)), encoding: .utf8)!
check("an editable focus is {\"editable\":true}", plain == "{\"editable\":true}")
let off = String(data: try! JSONEncoder().encode(TextFocus.none), encoding: .utf8)!
check("no focus is {\"editable\":false}", off == "{\"editable\":false}")
let secure = try! JSONDecoder().decode(TextFocus.self, from: Data("{\"editable\":true,\"secure\":true}".utf8))
check("a password field read back", secure == TextFocus(editable: true, secure: true))
check("an unknown field is skipped", (try? JSONDecoder().decode(TextFocus.self, from: Data("{\"editable\":false,\"caret\":[1,2]}".utf8))) == TextFocus.none)
check("generation 1", TextFocus.generation == 1)

// MARK: The hello
let hello = Hello(appVersion: "0.6.2", device: "Fold", textFocus: 1)
let helloJSON = try! JSONEncoder().encode(hello)
check("the hello carries textFocus", String(data: helloJSON, encoding: .utf8)!.contains("\"textFocus\":1"))
check("the hello reads back", (try? JSONDecoder().decode(Hello.self, from: helloJSON))?.textFocus == 1)
check("an older device's hello has none", (try? JSONDecoder().decode(Hello.self, from: Data("{\"appVersion\":\"0.6.1\"}".utf8)))?.textFocus == nil)
check("left out when nil", !String(data: try! JSONEncoder().encode(Hello(appVersion: "1")), encoding: .utf8)!.contains("textFocus"))

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
