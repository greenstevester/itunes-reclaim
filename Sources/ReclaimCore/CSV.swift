import Foundation

/// Minimal RFC 4180-ish CSV parser: handles quoted fields, escaped quotes (""),
/// commas inside quotes, and CRLF/LF line endings. Drops fully blank lines.
///
/// Iterates over unicode scalars rather than `Character`s on purpose: Swift
/// collapses a CRLF into a single `Character` grapheme cluster, which would
/// otherwise hide the line break from the `\r`/`\n` cases below.
public func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var record: [String] = []
    var field = ""
    var inQuotes = false
    let scalars = Array(text.unicodeScalars)
    var i = 0
    while i < scalars.count {
        let c = scalars[i]
        if inQuotes {
            if c == "\"" {
                if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                field.unicodeScalars.append(c)
            }
        } else {
            switch c {
            case "\"":
                inQuotes = true
            case ",":
                record.append(field); field = ""
            case "\n":
                record.append(field); field = ""
                rows.append(record); record = []
            case "\r":
                break // part of CRLF; the \n handles the line break
            default:
                field.unicodeScalars.append(c)
            }
        }
        i += 1
    }
    if !field.isEmpty || !record.isEmpty {
        record.append(field)
        rows.append(record)
    }
    return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
}
