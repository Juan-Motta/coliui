import ColiUICore
import Foundation
import Observation

/// One line of the Inspect tree: a value, a branch's opening line, or its closing bracket.
struct InspectRow: Identifiable, Equatable {
    enum Kind: Equatable { case string, number, bool, null, open, close }

    let id: String
    let path: String
    let depth: Int
    /// `"Name"` for object members, the index for array items, nil for the root and closing lines.
    let key: String?
    let value: String
    let kind: Kind
    let isBranch: Bool
    let isExpanded: Bool
    /// `{ 3 keys }` / `[ 1 item ]` on a collapsed branch.
    let summary: String
    /// What clicking the value copies: the plain value; nil for branches and brackets.
    let copyText: String?
}

/// Inspect.dc.html: `docker inspect` as a collapsible tree or raw JSON.
@MainActor
@Observable
final class InspectViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case tree = "Tree"
        case raw = "Raw"
        var id: Self { self }
    }

    enum State: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private static let root = "$"
    /// The branches the design shows open.
    static let defaultExpanded: Set<String> = [
        root, path(root, "State"), path(root, "Config"), path(root, "NetworkSettings"),
        path(path(root, "NetworkSettings"), "Ports"),
    ]

    var mode: Mode = .tree
    var filter = ""
    private(set) var state: State = .idle
    private(set) var value: JSONValue?
    private(set) var expanded = defaultExpanded

    let containerID: String
    private let inspector: ContainerInspector

    init(containerID: String, inspector: ContainerInspector) {
        self.containerID = containerID
        self.inspector = inspector
    }

    /// Fetches again each time the tab opens; what the user opened stays open.
    func load() async {
        if value == nil { state = .loading }
        do {
            value = try await inspector.inspect(id: containerID)
            state = .loaded
        } catch {
            value = nil
            state = .failed(error.localizedDescription)
        }
    }

    /// The same layout `docker inspect` prints: an array holding the container.
    var rawJSON: String {
        value.map { JSONValue.array([$0]).prettyPrinted() } ?? ""
    }

    var rows: [InspectRow] {
        guard let value else { return [] }
        let query = filter.trimmingCharacters(in: .whitespaces)
        return rows(for: value, key: nil, path: Self.root, depth: 0, query: query.isEmpty ? nil : query)
    }

    func toggle(_ row: InspectRow) {
        guard row.isBranch else { return }
        if expanded.contains(row.path) { expanded.remove(row.path) } else { expanded.insert(row.path) }
    }

    func expandAll() {
        guard let value else { return }
        var paths: Set<String> = []
        func visit(_ node: JSONValue, _ path: String) {
            switch node {
            case .object(let members):
                paths.insert(path)
                for member in members { visit(member.value, Self.path(path, member.key)) }
            case .array(let items):
                paths.insert(path)
                for (index, item) in items.enumerated() { visit(item, Self.path(path, String(index))) }
            default: break
            }
        }
        visit(value, Self.root)
        expanded = paths
    }

    func collapseAll() {
        expanded = [Self.root]
    }

    /// Keys may contain dots (labels), so path components use a separator JSON keys never hold.
    private static func path(_ parent: String, _ component: String) -> String {
        parent + "\u{1F}" + component
    }

    /// With a query, keeps rows whose key or value matches plus their parents (shown open);
    /// a matching branch keeps everything under it.
    private func rows(for node: JSONValue, key: String?, path: String, depth: Int, query: String?) -> [InspectRow] {
        let keyMatches = query.map { key?.localizedCaseInsensitiveContains($0) ?? false } ?? true
        let children: [(key: String, display: String, value: JSONValue)]
        let open: String, close: String
        switch node {
        case .object(let members):
            children = members.map { ($0.key, JSONValue.quoted($0.key), $0.value) }
            (open, close) = ("{", "}")
        case .array(let items):
            children = items.enumerated().map { (String($0.offset), String($0.offset), $0.element) }
            (open, close) = ("[", "]")
        default:
            let (text, kind, copy) = Self.leaf(node)
            if let query, !keyMatches, !text.localizedCaseInsensitiveContains(query) { return [] }
            return [InspectRow(id: path, path: path, depth: depth, key: key, value: text, kind: kind,
                               isBranch: false, isExpanded: false, summary: "", copyText: copy)]
        }

        // A matching branch (or no query) shows normally; otherwise only matching descendants, opened.
        let childQuery = keyMatches ? nil : query
        var below: [InspectRow] = []
        let isOpen = childQuery != nil || expanded.contains(path)
        if isOpen {
            for child in children {
                below += rows(for: child.value, key: child.display, path: Self.path(path, child.key), depth: depth + 1, query: childQuery)
            }
            if childQuery != nil, below.isEmpty { return [] }
        }
        let count = children.count
        let summary = isOpen ? "" : (open == "{"
            ? "{ \(count) \(count == 1 ? "key" : "keys") }"
            : "[ \(count) \(count == 1 ? "item" : "items") ]")
        var result = [InspectRow(id: path, path: path, depth: depth, key: key, value: isOpen ? open : "", kind: .open,
                                 isBranch: true, isExpanded: isOpen, summary: summary, copyText: nil)]
        result += below
        if isOpen, childQuery == nil {
            result.append(InspectRow(id: path + "\u{1F}close", path: path, depth: depth, key: nil, value: close, kind: .close,
                                     isBranch: false, isExpanded: false, summary: "", copyText: nil))
        }
        return result
    }

    private static func leaf(_ node: JSONValue) -> (text: String, kind: InspectRow.Kind, copy: String) {
        switch node {
        case .string(let text): (JSONValue.quoted(text), .string, text)
        case .number(let literal): (literal, .number, literal)
        case .bool(let flag): (flag ? "true" : "false", .bool, flag ? "true" : "false")
        default: ("null", .null, "null")
        }
    }
}
