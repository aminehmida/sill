/// Kind 64, host → device: whether the streamed app's focused element takes text, so a device can bring
/// up its own keyboard by itself when a text field is clicked on the Mac, and put it away when focus
/// leaves one. Only to a device whose hello says `textFocus` 1 or more, and only when it changes (and
/// once after that hello). Nothing of the field itself: no value, no title, no position.
public struct TextFocus: Codable, Sendable, Equatable {
    /// The focused element takes typed text: a text field, a text area, a search field, a combo box,
    /// a password field, or anything whose value can be set and that has a selection.
    public var editable: Bool
    /// A password field (AXSecureTextField). Only when `editable`; nil otherwise.
    public var secure: Bool?

    public init(editable: Bool, secure: Bool? = nil) {
        self.editable = editable
        self.secure = editable && secure == true ? true : nil
    }

    public static let none = TextFocus(editable: false)

    /// The generation of kind 64 this build sends or reads (Hello.textFocus).
    public static let generation = 1

    /// The rule, from what Accessibility says of the focused element: its role and subrole, whether
    /// its value can be set, and whether it has a selected text range. Pure, for the check.
    public static func judge(role: String?, subrole: String?, valueSettable: Bool, hasSelectedRange: Bool) -> TextFocus {
        if subrole == "AXSecureTextField" { return TextFocus(editable: true, secure: true) }
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField":
            return TextFocus(editable: true)
        default:
            break
        }
        if subrole == "AXSearchField" { return TextFocus(editable: true) }
        // A custom control or a web page's input: a settable value with a caret in it.
        if valueSettable && hasSelectedRange { return TextFocus(editable: true) }
        return .none
    }
}
