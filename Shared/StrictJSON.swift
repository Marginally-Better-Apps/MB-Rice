import Foundation

enum StrictJSON {
    static func checkDuplicateKeys(_ data: Data) throws {
        var parser = Parser(bytes: [UInt8](data))
        try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count else { throw RiceValidationError.invalid("Trailing JSON data") }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func space() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws {
            space()
            guard depth <= 32, index < bytes.count else { throw RiceValidationError.invalid("JSON nesting limit") }
            if bytes[index] == 123 { try object(depth: depth + 1) }
            else if bytes[index] == 91 { try array(depth: depth + 1) }
            else if bytes[index] == 34 { _ = try string() }
            else {
                let start = index
                while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw RiceValidationError.invalid("Invalid JSON value") }
            }
        }

        mutating func object(depth: Int) throws {
            index += 1
            space()
            var keys: Set<String> = []
            if consume(125) { return }
            while true {
                space()
                let key = try string()
                guard keys.insert(key).inserted else { throw RiceValidationError.invalid("Duplicate JSON key: \(key)") }
                space()
                guard consume(58) else { throw RiceValidationError.invalid("Invalid JSON object") }
                try value(depth: depth)
                space()
                if consume(125) { return }
                guard consume(44) else { throw RiceValidationError.invalid("Invalid JSON object") }
            }
        }

        mutating func array(depth: Int) throws {
            index += 1
            space()
            if consume(93) { return }
            while true {
                try value(depth: depth)
                space()
                if consume(93) { return }
                guard consume(44) else { throw RiceValidationError.invalid("Invalid JSON array") }
            }
        }

        mutating func string() throws -> String {
            guard consume(34) else { throw RiceValidationError.invalid("Expected JSON string") }
            let start = index - 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if escaped { escaped = false; continue }
                if byte == 92 { escaped = true; continue }
                if byte == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                }
                if byte < 32 { throw RiceValidationError.invalid("Invalid JSON string") }
            }
            throw RiceValidationError.invalid("Unterminated JSON string")
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            if index < bytes.count && bytes[index] == byte { index += 1; return true }
            return false
        }
    }
}
