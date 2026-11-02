/// A JSON document that keeps object keys in their original order, so `docker inspect` reads
/// the way Docker writes it. Numbers keep their literal text.
public indirect enum JSONValue: Equatable, Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    /// Two-space indentation, `"key": value`, empty containers as `{}` / `[]`: the `docker inspect` layout.
    public func prettyPrinted(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let lines = members.map { "\(inner)\(Self.quoted($0.key)): \($0.value.prettyPrinted(indent: indent + 1))" }
            return "{\n" + lines.joined(separator: ",\n") + "\n\(pad)}"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let lines = items.map { inner + $0.prettyPrinted(indent: indent + 1) }
            return "[\n" + lines.joined(separator: ",\n") + "\n\(pad)]"
        case .string(let text): return Self.quoted(text)
        case .number(let literal): return literal
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return "null"
        }
    }

    /// A JSON string literal: quotes, backslashes and control characters escaped.
    public static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20:
                result += "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count) + String(scalar.value, radix: 16)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

public struct JSONMember: Equatable, Sendable {
    public let key: String
    public let value: JSONValue

    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }
}
