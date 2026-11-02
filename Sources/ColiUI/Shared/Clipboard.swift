import AppKit

enum Clipboard {
    /// Replaces the general pasteboard's contents with `text`.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
