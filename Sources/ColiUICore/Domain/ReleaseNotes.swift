import Foundation

/// Release notes as `scripts/release-notes.sh` writes them: `## Section` headings over `- **scope:** text` bullets.
public enum ReleaseNotes {
    public struct Section: Equatable, Sendable {
        /// Nil for bullets that come before any heading.
        public let title: String?
        public let items: [Item]

        public init(title: String?, items: [Item]) {
            self.title = title
            self.items = items
        }
    }

    public struct Item: Equatable, Sendable {
        /// The conventional-commit scope ("app" in `feat(app): …`), shown in bold.
        public let scope: String?
        public let text: String

        public init(scope: String?, text: String) {
            self.scope = scope
            self.text = text
        }
    }

    public static func parse(_ markdown: String) -> [Section] {
        var sections: [Section] = []
        var title: String?
        var items: [Item] = []

        func flush() {
            if !items.isEmpty { sections.append(Section(title: title, items: items)) }
            items = []
        }

        for raw in markdown.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                flush()
                title = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                continue
            }
            var text = line
            if text.hasPrefix("- ") || text.hasPrefix("* ") { text = String(text.dropFirst(2)) }
            items.append(item(text))
        }
        flush()
        return sections
    }

    /// `**app:** add X` → scope "app", text "add X".
    private static func item(_ text: String) -> Item {
        guard text.hasPrefix("**"), let end = text.range(of: ":**", range: text.index(text.startIndex, offsetBy: 2)..<text.endIndex)
        else { return Item(scope: nil, text: text) }
        let scope = String(text[text.index(text.startIndex, offsetBy: 2)..<end.lowerBound])
        let rest = text[end.upperBound...].trimmingCharacters(in: .whitespaces)
        return Item(scope: scope, text: rest)
    }
}
