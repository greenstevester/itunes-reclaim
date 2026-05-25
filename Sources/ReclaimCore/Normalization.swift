import Foundation

/// Normalizes a title/artist/album for fuzzy matching: lowercase, fold diacritics,
/// `&`→`and`, drop `feat.`/`featuring …` segments, strip parenthetical/bracketed
/// noise, reduce punctuation to spaces, collapse whitespace. Stripping all
/// parentheticals can over-trim a rare title like "(Sittin' On) The Dock of the
/// Bay"; for matching, that trade-off favors recall and is acceptable.
public func normalize(_ s: String) -> String {
    var t = s.lowercased()
    t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    t = t.replacingOccurrences(of: "&", with: " and ")

    // Drop "feat. ..." / "featuring ..." through end of string.
    if let r = t.range(of: #"\b(feat\.?|featuring)\b.*$"#, options: .regularExpression) {
        t.removeSubrange(r)
    }
    // Remove (...) and [...] groups.
    t = t.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)

    // Reduce anything that isn't a letter/number to a space.
    let scalars = t.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    t = String(scalars)

    // Collapse runs of whitespace and trim.
    t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return t.trimmingCharacters(in: .whitespaces)
}
