import Foundation

/// The block-YAML subset clash proxy lists use: mappings and sequences nested
/// by indentation, quoted and plain scalars, flow lists, comments. A `- key: value`
/// item opens a map whose first line is the content at the column it starts on.
/// Ported from the Android client's `MiniYaml`.
enum MiniYaml {

    enum YamlError: Error {
        case nestingTooDeep
        case unterminatedValue
        case invalidMapping
    }

    struct Line {
        let indent: Int
        let text: String
    }

    final class Cursor {
        let lines: [Line]
        var index: Int
        init(_ lines: [Line], _ index: Int) {
            self.lines = lines
            self.index = index
        }
        var line: Line { lines[index] }
        func peek() -> Line? { index < lines.count ? lines[index] : nil }
    }

    static func parse(_ body: String) throws -> Any? {
        var lines: [Line] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if let stripped = strip(String(raw)) {
                lines.append(stripped)
            }
        }
        lines = lines.filter { $0.text != "---" && $0.text != "..." }
        guard let first = lines.first else { return nil }
        for line in lines where line.indent > 128 {
            throw YamlError.nestingTooDeep
        }
        return try block(Cursor(lines, 0), first.indent)
    }

    /// Blank and comment-only lines vanish; the rest keep their indent.
    private static func strip(_ raw: String) -> Line? {
        guard let indent = raw.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let text = stripComment(String(raw[indent...]).trimmingCharacters(in: .whitespaces))
        guard !text.isEmpty else { return nil }
        let column = raw.distance(from: raw.startIndex, to: indent)
        return Line(indent: column, text: text)
    }

    /// A `#` outside quotes starts a comment — but only at line start or after a space.
    private static func stripComment(_ text: String) -> String {
        var quote: Character? = nil
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if let q = quote {
                if q == "\"" && char == "\\" {
                    guard let after = text.index(index, offsetBy: 2, limitedBy: text.endIndex) else {
                        // Escape at line end: the quote never closes; keep the line.
                        return text
                    }
                    index = after
                    continue
                }
                if char == q {
                    if q == "'", text.index(after: index) < text.endIndex,
                       text[text.index(after: index)] == "'" {
                        index = text.index(index, offsetBy: 2)
                        continue
                    }
                    quote = nil
                }
            } else {
                switch char {
                case "'", "\"":
                    quote = char
                case "#":
                    if index == text.startIndex || text[text.index(before: index)].isWhitespace {
                        return String(text[..<index]).trimmingCharacters(in: .whitespaces)
                    }
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return text
    }

    private static func isSeqItem(_ text: String) -> Bool {
        text == "-" || text.hasPrefix("- ")
    }

    private static func block(_ cursor: Cursor, _ indent: Int) throws -> Any? {
        try isSeqItem(cursor.line.text) ? sequence(cursor, indent) : mapping(cursor, indent)
    }

    private static func sequence(_ cursor: Cursor, _ indent: Int) throws -> [Any?] {
        var items: [Any?] = []
        while cursor.peek()?.indent == indent, isSeqItem(cursor.line.text) {
            let line = cursor.line
            if line.text == "-" {
                cursor.index += 1
                if let next = cursor.peek(), next.indent > indent {
                    items.append(try block(cursor, next.indent))
                } else {
                    items.append(nil)
                }
            } else {
                let content = String(line.text.dropFirst("- ".count))
                if content.hasPrefix("{") && content.hasSuffix("}") {
                    cursor.index += 1
                    items.append(try scalar(content))
                } else if keyValue(content) != nil {
                    // The map opens mid-line, at the column the content starts on;
                    // the whole item line is spent as that opening.
                    cursor.index += 1
                    let virtual = Line(
                        indent: line.indent + line.text.count - content.count,
                        text: content
                    )
                    items.append(try mapping(cursor, virtual.indent, first: virtual))
                } else {
                    cursor.index += 1
                    items.append(try scalar(content))
                }
            }
        }
        return items
    }

    /// A block mapping at `indent`; `first` is a virtual opening line from a sequence item.
    private static func mapping(_ cursor: Cursor, _ indent: Int, first: Line? = nil) throws -> [String: Any?] {
        var map: [String: Any?] = [:]
        var current = first
        while true {
            let line: Line
            if let c = current {
                line = c
            } else if let peeked = cursor.peek(), peeked.indent == indent {
                line = peeked
            } else {
                break
            }
            if current == nil && isSeqItem(line.text) { break }
            guard let entry = keyValue(line.text) else { break }
            if current == nil { cursor.index += 1 }
            current = nil
            let (key, valueText) = entry
            if valueText.isEmpty {
                // A child block below, or a sequence written at the key's own indent.
                if let next = cursor.peek() {
                    if next.indent > indent {
                        map[key] = try block(cursor, next.indent)
                    } else if next.indent == indent && isSeqItem(next.text) {
                        map[key] = try sequence(cursor, indent)
                    } else {
                        map[key] = nil
                    }
                } else {
                    map[key] = nil
                }
            } else {
                map[key] = try scalar(valueText)
            }
        }
        return map
    }

    /// `key: value` — the first colon outside quotes that ends the key.
    private static func keyValue(_ text: String) -> (String, String)? {
        guard let index = try? delimiter(text, ":") else { return nil }
        let rest = String(text[text.index(after: index)...])
        if !rest.isEmpty && !rest[rest.startIndex].isWhitespace { return nil }
        return (unquote(String(text[..<index]).trimmingCharacters(in: .whitespaces)),
                rest.trimmingCharacters(in: .whitespaces))
    }

    private static func scalar(_ text: String) throws -> Any {
        if text.hasPrefix("[") && text.hasSuffix("]") {
            let inner = String(text.dropFirst().dropLast())
            return try splitFlow(inner)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { try scalar($0.trimmingCharacters(in: .whitespaces)) }
        }
        if text.hasPrefix("{") && text.hasSuffix("}") {
            let inner = String(text.dropFirst().dropLast())
            var map: [String: Any?] = [:]
            for entry in try splitFlow(inner) {
                guard let colon = try delimiter(entry, ":") else { throw YamlError.invalidMapping }
                let key = unquote(String(entry[..<colon]).trimmingCharacters(in: .whitespaces))
                map[key] = try scalar(String(entry[entry.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces))
            }
            return map
        }
        return unquote(text)
    }

    private static func splitFlow(_ text: String) throws -> [String] {
        var result: [String] = []
        var start = text.startIndex
        for index in try delimiters(text, ",") + [text.endIndex] {
            result.append(String(text[start..<index]))
            guard index < text.endIndex else { break }
            start = text.index(after: index)
        }
        return result
    }

    private static func delimiter(_ text: String, _ target: Character) throws -> String.Index? {
        try delimiters(text, target).first
    }

    private static func delimiters(_ text: String, _ target: Character) throws -> [String.Index] {
        var positions: [String.Index] = []
        var quote: Character? = nil
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if let q = quote {
                if q == "\"" && char == "\\" {
                    guard text.index(index, offsetBy: 2, limitedBy: text.endIndex) != nil else {
                        throw YamlError.unterminatedValue
                    }
                    index = text.index(index, offsetBy: 2)
                    continue
                }
                if char == q {
                    if q == "'", text.index(after: index) < text.endIndex,
                       text[text.index(after: index)] == "'" {
                        index = text.index(index, offsetBy: 2)
                        continue
                    }
                    quote = nil
                }
            } else {
                switch char {
                case "'", "\"":
                    quote = char
                case "[", "{":
                    depth += 1
                case "]", "}":
                    depth -= 1
                case target:
                    if depth == 0 { positions.append(index) }
                default:
                    break
                }
            }
            if !(0...64).contains(depth) { throw YamlError.nestingTooDeep }
            index = text.index(after: index)
        }
        if quote != nil || depth != 0 { throw YamlError.unterminatedValue }
        return positions
    }

    private static func unquote(_ text: String) -> String {
        if text.count >= 2 && text.hasPrefix("'") && text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if text.count >= 2 && text.hasPrefix("\"") && text.hasSuffix("\"") {
            if let data = text.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(
                   with: data, options: [.fragmentsAllowed]
               ) as? String {
                return parsed
            }
            // Not JSON-escaped: keep the inner text verbatim.
            return String(text.dropFirst().dropLast())
        }
        return text
    }
}
