import Foundation

extension JSONValue {
    /// Parses one JSON document; `JSONSerialization` would lose the key order.
    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: [UInt8](data))
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw DockerError.malformedResponse }
        return value
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func value() throws -> JSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw DockerError.malformedResponse }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return .number(try number())
        }
    }

    private mutating func object() throws -> JSONValue {
        index += 1
        var members: [JSONMember] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw DockerError.malformedResponse }
            let key = try string()
            try expect(":")
            members.append(JSONMember(key: key, value: try value()))
            if try separator(closing: "}") { return .object(members) }
        }
    }

    private mutating func array() throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            items.append(try value())
            if try separator(closing: "]") { return .array(items) }
        }
    }

    /// Consumes `,` (more to come: false) or the closing bracket (done: true).
    private mutating func separator(closing: Character) throws -> Bool {
        skipWhitespace()
        guard index < bytes.count else { throw DockerError.malformedResponse }
        let byte = bytes[index]
        index += 1
        if byte == UInt8(ascii: ",") { return false }
        if byte == closing.asciiValue { return true }
        throw DockerError.malformedResponse
    }

    private mutating func expect(_ character: Character) throws {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == character.asciiValue else { throw DockerError.malformedResponse }
        index += 1
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.utf8)
        guard bytes.count - index >= expected.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw DockerError.malformedResponse
        }
        index += expected.count
    }

    private mutating func number() throws -> String {
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        let literal = String(decoding: bytes[start..<index], as: UTF8.self)
        guard !literal.isEmpty, Double(literal) != nil else { throw DockerError.malformedResponse }
        return literal
    }

    private mutating func string() throws -> String {
        index += 1
        var scalars = String.UnicodeScalarView()
        var run = [UInt8]()
        func flush() {
            scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
            run.removeAll(keepingCapacity: true)
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                flush()
                return String(scalars)
            case UInt8(ascii: "\\"):
                flush()
                guard index < bytes.count else { throw DockerError.malformedResponse }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"): scalars.append(try unicodeEscape())
                default: throw DockerError.malformedResponse
                }
            default:
                run.append(byte)
            }
        }
        throw DockerError.malformedResponse
    }

    /// `\uXXXX`, joining a UTF-16 surrogate pair into one scalar; a lone surrogate becomes U+FFFD.
    private mutating func unicodeEscape() throws -> Unicode.Scalar {
        let high = try hex4()
        if (0xD800..<0xDC00).contains(high), bytes.count - index >= 6,
           bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
            let resume = index
            index += 2
            let low = try hex4()
            if (0xDC00..<0xE000).contains(low) {
                return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)) ?? "\u{FFFD}"
            }
            // Not a pair: the next escape is a character of its own.
            index = resume
            return "\u{FFFD}"
        }
        return Unicode.Scalar(high) ?? "\u{FFFD}"
    }

    private mutating func hex4() throws -> UInt32 {
        guard bytes.count - index >= 4,
              let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
            throw DockerError.malformedResponse
        }
        index += 4
        return value
    }
}
