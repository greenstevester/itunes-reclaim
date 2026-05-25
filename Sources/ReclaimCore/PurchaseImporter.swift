import Foundation

public struct ColumnMapping: Equatable {
    public var title: Int?
    public var artist: Int?
    public var album: Int?
    public var date: Int?
    public var storeID: Int?
    public init() {}
}

public enum ImportError: Error, Equatable {
    case empty
    case noTitleColumn
}

/// Auto-detects column indices from a CSV header. Detection order matters:
/// storeID and artist are claimed before title so a "name"/"item" substring in
/// "Artist Name"/"Item ID" doesn't get mis-assigned to title.
public func detectColumns(header: [String]) -> ColumnMapping {
    let names = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    var used = Set<Int>()

    func find(_ synonyms: [String]) -> Int? {
        for (i, name) in names.enumerated() where !used.contains(i) && synonyms.contains(name) {
            used.insert(i); return i
        }
        for (i, name) in names.enumerated()
        where !used.contains(i) && synonyms.contains(where: { name.contains($0) }) {
            used.insert(i); return i
        }
        return nil
    }

    var m = ColumnMapping()
    m.storeID = find(["content id", "item id", "adam id", "apple id"])
    m.artist  = find(["artist name", "artist"])
    m.album   = find(["collection name", "album", "collection"])
    m.date    = find(["purchase date", "transaction date", "order date", "date"])
    m.title   = find(["title", "name", "song", "track", "item", "description"])
    return m
}

private let dateFormats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"]

private func parseDate(_ raw: String) -> Date? {
    guard !raw.isEmpty else { return nil }
    if let d = ISO8601DateFormatter().date(from: raw) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in dateFormats {
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return d }
    }
    return nil
}

/// Parses a purchases CSV into canonical `PurchasedItem`s. Uses `mapping` if given,
/// otherwise auto-detects. Rows with a blank title are skipped.
public func importPurchases(csv: String, mapping: ColumnMapping? = nil) throws -> [PurchasedItem] {
    let rows = parseCSV(csv)
    guard let header = rows.first else { throw ImportError.empty }
    let map = mapping ?? detectColumns(header: header)
    guard let titleIdx = map.title else { throw ImportError.noTitleColumn }

    func cell(_ row: [String], _ idx: Int?) -> String {
        guard let i = idx, i >= 0, i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    return rows.dropFirst().compactMap { row in
        let title = cell(row, titleIdx)
        guard !title.isEmpty else { return nil }
        let store = cell(row, map.storeID)
        return PurchasedItem(
            title: title,
            artist: cell(row, map.artist),
            album: cell(row, map.album),
            purchaseDate: parseDate(cell(row, map.date)),
            storeID: store.isEmpty ? nil : store
        )
    }
}
